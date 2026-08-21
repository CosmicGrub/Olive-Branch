// OLIVE BRANCH — two truths and a tall tale. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §9.2,
// §8.11.1, P2. Renders MARKUP screen 'gamePicker' catalogue entry
// 'twoTruths'.
//
// Play Together Phase 1, Batch B (docs/superpowers/specs/
// 2026-08-20-play-together-phase1-design.md) — third of four
// curated-prompt activities. Co-op, minAge 6 — competitive: false, no
// handicaps, `story`'s exact catalogue shape.
//
// ============================================================================
// THE SAFE-CONTENT MECHANISM — read this before touching the data below.
// ============================================================================
// The spec flags this ONE activity by name as needing real design judgment:
// the classic party game has each PLAYER invent their own two true facts and
// one lie about themselves, which is exactly the open-text, real-personal-
// information risk the spec's "Content strategy" section exists to close.
// The spec's own worked examples for a category — "a place you've been,"
// "something you're good at" — are still personal-fact categories; naming
// them was the prompt illustrating the SHAPE of the classic game, not
// blessing that shape as safe. It is not safe here: even with no `TextField`
// anywhere, a category like "a place you've been" still pressures a child to
// think of and say a real true fact about her own life on camera-adjacent
// shared-device play, and a "tall tale" alongside it still implies the
// TRUTHS were personal. That is the same risk the spec's "never free text"
// rule targets, just moved from typing to speaking — closing the typed
// channel while leaving the spoken one open would be a technicality, not
// actual safety.
//
// The mechanism actually shipped here: EVERY statement — both truths and
// the tall tale — is fixed, in-repo, curated trivia the app itself
// authored, about the WORLD (animals, space, the ocean, food, geography),
// never about either player. `TallTaleRoundSet` has no field for a player's
// name, location, or personal history, structurally, not just by
// convention — there is nothing in this file's data shape a personal fact
// could even be entered into. The "two truths" are genuine, kid-appropriate
// trivia; the "tall tale" is a curated, obviously-silly-on-reflection false
// claim in the same category and register, written to sound plausible for a
// few seconds — the same fun the classic game has, with the risk surface
// removed rather than trusted to good behavior in the moment. This is the
// SAFEST, most conservative reading of the spec's mandate available: it
// keeps the "spot the fib" mechanic the activity is named for while making
// "safe without a hovering adult" true by construction, matching the same
// standard `game_guess_doodle.dart`'s curated word bank already set.
//
// The category itself is ALSO a curated, tappable choice (`tallTaleCategories`
// — five fixed labels), not a text field and not left to chance alone: the
// presenter picks which trivia flavor to play, then the app randomly deals
// one of that category's curated round sets. This mirrors
// `game_twenty_questions.dart`'s own category-chip picker for the same
// reason — a real choice from a fixed list, never open text — so the two
// files that most needed a safe-content answer converged on the same
// pattern independently, which is itself a small confirmation the pattern
// is right rather than arbitrary.
//
// Mechanically: whoever is currently 'the presenter' (swappable any time via
// the same actor toggle `game_guess_doodle.dart`'s artist switch uses, never
// a turn lock) is privately shown WHICH of the three shuffled statements is
// the tall tale — "keep this facing you," the same honor-system convention
// `game_guess_doodle.dart`'s secret word already relies on for local
// pass-and-play, since there is no way to hide pixels from someone sharing
// the same physical screen. The presenter reads all three aloud; the other
// person taps which one they think is fake. The outcome is deliberately
// soft and never tallied — `revealed`/`guessIndex` are per-round UI state
// only, reset by every new round, the same "transient, not tallied" shape
// `game_guess_doodle.dart`'s `_revealed`/`_gotIt` already use.
import 'dart:math';

import 'package:flutter/material.dart';
import 'game_curated_activity.dart';

// ============================================================ prompt bank ==
// Real, drafted content — not a placeholder. Five categories, six round
// sets each (30 total, 90 curated statements), reviewed for tone: silly and
// warm, never a values judgment, nothing frightening, and never personal —
// see the file header for why that last property is load-bearing here.

class TallTaleRoundSet {
  const TallTaleRoundSet({required this.id, required this.category, required this.truthA, required this.truthB, required this.tallTale});
  final String id;
  final String category;
  final String truthA;
  final String truthB;
  final String tallTale;
}

const String catAnimals = 'Animal facts';
const String catSpace = 'Space & sky';
const String catOcean = 'Ocean life';
const String catFood = 'Food & cooking';
const String catWorld = 'Around the world';

/// The only categories a presenter may ever pick — a fixed, curated list,
/// never open text.
const List<String> tallTaleCategories = <String>[catAnimals, catSpace, catOcean, catFood, catWorld];

const List<TallTaleRoundSet> tallTaleRoundSets = <TallTaleRoundSet>[
  TallTaleRoundSet(id: 'animals-1', category: catAnimals,
    truthA: 'Octopuses have three hearts.',
    truthB: 'A group of flamingos is called a flamboyance.',
    tallTale: 'Elephants can jump higher than a house.'),
  TallTaleRoundSet(id: 'animals-2', category: catAnimals,
    truthA: 'A snail can sleep for three years.',
    truthB: 'Butterflies taste with their feet.',
    tallTale: 'Goldfish can ride bicycles if you teach them young enough.'),
  TallTaleRoundSet(id: 'animals-3', category: catAnimals,
    truthA: "A shrimp's heart is located in its head.",
    truthB: 'Koalas sleep up to twenty hours a day.',
    tallTale: 'Penguins can fly backward faster than they can fly forward.'),
  TallTaleRoundSet(id: 'animals-4', category: catAnimals,
    truthA: 'A cheetah cannot roar — it chirps and purrs instead.',
    truthB: 'Some turtles can breathe through their bottoms.',
    tallTale: 'Squirrels can talk if they eat enough acorns.'),
  TallTaleRoundSet(id: 'animals-5', category: catAnimals,
    truthA: 'A group of owls is called a parliament.',
    truthB: "Sea otters hold hands while they sleep so they don't drift apart.",
    tallTale: 'Ladybugs count their own spots every morning.'),
  TallTaleRoundSet(id: 'animals-6', category: catAnimals,
    truthA: "Kangaroos can't walk backward.",
    truthB: "A blue whale's heart is about the size of a small car.",
    tallTale: "Hedgehogs change the color of their spikes when they're happy."),
  TallTaleRoundSet(id: 'space-1', category: catSpace,
    truthA: 'A day on Venus is longer than its whole year.',
    truthB: 'There are more stars in the sky than grains of sand on every beach on Earth.',
    tallTale: 'Astronauts can hear thunder on the Moon.'),
  TallTaleRoundSet(id: 'space-2', category: catSpace,
    truthA: 'The Sun is so big that about one million Earths could fit inside it.',
    truthB: 'Saturn would float if you put it in a giant bathtub of water.',
    tallTale: 'Shooting stars are actually tiny stars falling asleep.'),
  TallTaleRoundSet(id: 'space-3', category: catSpace,
    truthA: 'Some parts of the Moon are colder than anywhere on Earth.',
    truthB: 'Jupiter has at least ninety moons of its own.',
    tallTale: 'If you shout in space, the stars shout back.'),
  TallTaleRoundSet(id: 'space-4', category: catSpace,
    truthA: 'A year on Mercury is only about 88 Earth days long.',
    truthB: 'The footprints astronauts left on the Moon could stay there for millions of years.',
    tallTale: 'Rainbows can be seen at night if the moon is full enough.'),
  TallTaleRoundSet(id: 'space-5', category: catSpace,
    truthA: "Space is completely silent because there's no air to carry sound.",
    truthB: 'Neptune has winds faster than any storm on Earth.',
    tallTale: 'The Sun turns off every night to let the stars rest.'),
  TallTaleRoundSet(id: 'space-6', category: catSpace,
    truthA: 'It takes about eight minutes for sunlight to reach your eyes from the Sun.',
    truthB: 'Some comets have tails that stretch for millions of miles.',
    tallTale: 'Astronauts grow a whole inch taller for every single day they nap in space.'),
  TallTaleRoundSet(id: 'ocean-1', category: catOcean,
    truthA: "A blue whale's tongue can weigh as much as an elephant.",
    truthB: "Sea stars don't have brains at all.",
    tallTale: 'Dolphins can hold their breath for an entire week.'),
  TallTaleRoundSet(id: 'ocean-2', category: catOcean,
    truthA: 'Some jellyfish have been around longer than dinosaurs.',
    truthB: 'A group of jellyfish is called a smack.',
    tallTale: 'Crabs can grow a brand new claw overnight if they lose one.'),
  TallTaleRoundSet(id: 'ocean-3', category: catOcean,
    truthA: 'Seahorses are the only fish where the dad carries the babies.',
    truthB: "The ocean has mountains taller than Mount Everest — they're just underwater.",
    tallTale: 'Starfish can regrow their whole body from just one eyelash-sized piece.'),
  TallTaleRoundSet(id: 'ocean-4', category: catOcean,
    truthA: "Some fish can change from one gender to another during their life.",
    truthB: "An octopus can squeeze through any gap bigger than its beak.",
    tallTale: 'Whales can hold a conversation in English if you talk to them slowly enough.'),
  TallTaleRoundSet(id: 'ocean-5', category: catOcean,
    truthA: 'The ocean is home to the largest animal that has ever lived — the blue whale.',
    truthB: 'Clownfish are immune to the sting of the sea anemones they live in.',
    tallTale: "Sharks sneeze bubbles whenever they smell something they don't like."),
  TallTaleRoundSet(id: 'ocean-6', category: catOcean,
    truthA: 'Some fish glow in the dark all on their own.',
    truthB: "A giant squid's eyes can be as big as a dinner plate.",
    tallTale: 'Lobsters turn bright red the moment they get embarrassed.'),
  TallTaleRoundSet(id: 'food-1', category: catFood,
    truthA: 'Honey never spoils, even after thousands of years.',
    truthB: 'Carrots used to be purple before people grew them orange.',
    tallTale: 'Broccoli was invented by a chef who really disliked candy.'),
  TallTaleRoundSet(id: 'food-2', category: catFood,
    truthA: "Bananas are berries, but strawberries technically aren't.",
    truthB: 'Popcorn can jump up to three feet in the air when it pops.',
    tallTale: 'If you plant a french fry, a whole potato plant grows overnight.'),
  TallTaleRoundSet(id: 'food-3', category: catFood,
    truthA: "Apples float in water because they're about 25% air.",
    truthB: 'It takes almost a year for a pineapple to grow.',
    tallTale: 'Cheese gets sleepy and takes naps if you leave it out too long.'),
  TallTaleRoundSet(id: 'food-4', category: catFood,
    truthA: "Peanuts aren't technically nuts — they're legumes, like beans.",
    truthB: "A single spaghetti noodle is called a 'spaghetto.'",
    tallTale: 'Pizza was originally delivered by trained pigeons.'),
  TallTaleRoundSet(id: 'food-5', category: catFood,
    truthA: 'Some watermelons are grown in square shapes to fit better in fridges.',
    truthB: 'Chocolate was once so valuable it was used as money.',
    tallTale: 'If you whisper to a lemon, it turns sweeter.'),
  TallTaleRoundSet(id: 'food-6', category: catFood,
    truthA: 'It takes about 500 lemons to fill a bathtub with lemonade.',
    truthB: 'Cucumbers are made up of about 95% water.',
    tallTale: 'Grapes explode like tiny fireworks if you leave them in the sun for a week.'),
  TallTaleRoundSet(id: 'world-1', category: catWorld,
    truthA: 'In Japan, there are more pets than children.',
    truthB: 'The Great Wall of China is thousands of miles long.',
    tallTale: "In France, it's against the law to feel bored."),
  TallTaleRoundSet(id: 'world-2', category: catWorld,
    truthA: 'Iceland has almost no mosquitoes at all.',
    truthB: 'Australia is both a country and a continent.',
    tallTale: 'In Canada, moose deliver the mail in small towns.'),
  TallTaleRoundSet(id: 'world-3', category: catWorld,
    truthA: 'There is a hotel in Sweden made almost entirely of ice.',
    truthB: 'Brazil is home to the largest rainforest in the world.',
    tallTale: 'In Switzerland, cows wear tiny hats to stay warm in winter.'),
  TallTaleRoundSet(id: 'world-4', category: catWorld,
    truthA: 'Russia is so big it spans eleven time zones.',
    truthB: "In some parts of Norway, the sun doesn't set at all in summer.",
    tallTale: 'In Egypt, camels are required to wear seatbelts.'),
  TallTaleRoundSet(id: 'world-5', category: catWorld,
    truthA: 'The Netherlands has more bicycles than people.',
    truthB: "Mount Everest grows a few millimeters taller every year.",
    tallTale: 'In Italy, pizza toppings are picked by a town vote every spring.'),
  TallTaleRoundSet(id: 'world-6', category: catWorld,
    truthA: "Antarctica is the world's largest desert.",
    truthB: 'There are more than seven thousand languages spoken around the world.',
    tallTale: 'In Peru, llamas are trained to direct traffic in busy cities.'),
];

// ================================================================ engine ===

class TallTaleStatement {
  const TallTaleStatement({required this.text, required this.isTallTale});
  final String text;
  final bool isTallTale;
}

class TallTaleRound {
  const TallTaleRound({required this.setId, required this.category, required this.statements, this.guessIndex, this.revealed = false});
  final String setId;
  final String category;

  /// Exactly three, shuffled — the presenter alone learns which index is
  /// the tall tale (see file header on the honor-system reveal).
  final List<TallTaleStatement> statements;
  final int? guessIndex;
  final bool revealed;

  int get tallTaleIndex => statements.indexWhere((s) => s.isTallTale);
  bool? get guessedCorrectly => guessIndex == null ? null : guessIndex == tallTaleIndex;

  TallTaleRound withGuess(int index) =>
      TallTaleRound(setId: setId, category: category, statements: statements, guessIndex: index, revealed: true);
}

TallTaleRound newRound(String category, Random random, {String? excludingSetId}) {
  final List<TallTaleRoundSet> candidates = tallTaleRoundSets.where((TallTaleRoundSet s) => s.category == category).toList();
  TallTaleRoundSet set;
  if (candidates.length <= 1) {
    set = candidates.first;
  } else {
    do {
      set = candidates[random.nextInt(candidates.length)];
    } while (set.id == excludingSetId);
  }
  final List<TallTaleStatement> statements = <TallTaleStatement>[
    TallTaleStatement(text: set.truthA, isTallTale: false),
    TallTaleStatement(text: set.truthB, isTallTale: false),
    TallTaleStatement(text: set.tallTale, isTallTale: true),
  ]..shuffle(random);
  return TallTaleRound(setId: set.id, category: category, statements: statements);
}

// ================================================================ widget ===

class TwoTruthsScreen extends StatefulWidget {
  const TwoTruthsScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad', this.random});
  final String childName;
  final String parentName;

  /// Injectable for tests only, matching `game_guess_doodle.dart`'s own
  /// convention — production always uses a real, unseeded Random().
  final Random? random;

  @override
  State<TwoTruthsScreen> createState() => _TwoTruthsScreenState();
}

class _TwoTruthsScreenState extends State<TwoTruthsScreen> {
  late final Random _random = widget.random ?? Random();
  TallTaleRound? _round;
  final List<String> _history = <String>[];

  /// 'child' or 'parent' — whoever currently knows which statement is the
  /// tall tale. Swappable any time; not a turn lock, never counted.
  String _presenterId = 'child';

  String _name(String id) => id == 'child' ? widget.childName : widget.parentName;

  void _pickCategory(String category) => setState(() {
        _round = newRound(category, _random);
      });

  void _guess(int index) {
    final TallTaleRound? round = _round;
    if (round == null || round.revealed) return;
    setState(() {
      final TallTaleRound revealed = round.withGuess(index);
      _round = revealed;
      final String outcome = revealed.guessedCorrectly! ? 'spotted the tall tale!' : 'was fooled — nicely done.';
      _history.add('${revealed.category}: "${revealed.statements[revealed.tallTaleIndex].text}" — $outcome');
    });
  }

  void _newRound() => setState(() => _round = null);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Two truths and a tall tale')),
      body: SafeArea(
        child: CuratedActivityLayout(
          main: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text('Two are true. Can she guess the made-up one?',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Expanded(
                child: _round == null
                    ? _CategoryPicker(onPick: _pickCategory)
                    : _RoundView(
                        round: _round!,
                        presenterId: _presenterId,
                        presenterName: _name(_presenterId),
                        childName: widget.childName,
                        parentName: widget.parentName,
                        onPresenterChanged: (String id) => setState(() => _presenterId = id),
                        onGuess: _guess,
                        onNewRound: _newRound,
                      ),
              ),
            ]),
          ),
          history: SessionHistoryPanel(
            title: 'Tall tales so far',
            entries: _history,
            emptyHint: 'Your first solved round will show up here.',
          ),
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        const Text('Pick a category:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            key: const Key('categoryList'),
            children: <Widget>[
              for (final String category in tallTaleCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.tonal(onPressed: () => onPick(category), child: Text(category)),
                  ),
                ),
            ],
          ),
        ),
      ]);
}

class _RoundView extends StatelessWidget {
  const _RoundView({
    required this.round,
    required this.presenterId,
    required this.presenterName,
    required this.childName,
    required this.parentName,
    required this.onPresenterChanged,
    required this.onGuess,
    required this.onNewRound,
  });

  final TallTaleRound round;
  final String presenterId;
  final String presenterName;
  final String childName;
  final String parentName;
  final ValueChanged<String> onPresenterChanged;
  final ValueChanged<int> onGuess;
  final VoidCallback onNewRound;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text("Who's presenting?", style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      SegmentedButton<String>(
        style: SegmentedButton.styleFrom(minimumSize: const Size(64, 48)),
        segments: <ButtonSegment<String>>[
          ButtonSegment<String>(value: 'child', label: Text(childName)),
          ButtonSegment<String>(value: 'parent', label: Text(parentName)),
        ],
        selected: <String>{presenterId},
        onSelectionChanged: (Set<String> s) => onPresenterChanged(s.first),
      ),
      const SizedBox(height: 12),
      Text(round.category, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 8),
      if (!round.revealed) ...[
        Container(
          key: const Key('tallTaleHint'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Text('$presenterName — statement #${round.tallTaleIndex + 1} is the tall tale. Keep this facing you!',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: scheme.onTertiaryContainer)),
        ),
        const SizedBox(height: 12),
      ],
      Expanded(
        child: ListView(
          key: const Key('statementList'),
          children: <Widget>[
            for (int i = 0; i < round.statements.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: round.revealed ? null : () => onGuess(i),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14), alignment: Alignment.centerLeft),
                    child: Text('${i + 1}. ${round.statements[i].text}',
                        style: TextStyle(
                          fontWeight: round.revealed && round.statements[i].isTallTale ? FontWeight.w700 : FontWeight.w400,
                        )),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (round.revealed) ...[
        const SizedBox(height: 4),
        Text(
          key: const Key('tallTaleResult'),
          round.guessedCorrectly!
              ? '$presenterName\'s tall tale was spotted!'
              : 'The tall tale got past them this time.',
          style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.tonal(onPressed: onNewRound, child: const Text('New round')),
        ),
      ],
    ]);
  }
}
