// OLIVE BRANCH — 20 questions. Verified by CI (a Flutter toolchain now runs
// for real in tools/verify.sh's automated pipeline — also manually built
// and run via `flutter analyze` / `flutter test` this session; CHANGELOG
// v0.49.61). MASTERFILE §9.2, §8.11.1, P2. Renders MARKUP screen
// 'gamePicker' catalogue entry 'twentyQuestions'.
//
// Play Together Phase 1, Batch B (docs/superpowers/specs/
// 2026-08-20-play-together-phase1-design.md) — fourth of four
// curated-prompt activities. Co-op, minAge 5 — competitive: false, no
// handicaps, `story`'s exact catalogue shape.
//
// Content source: the secret is ALWAYS picked from a curated category —
// `twentyQuestionsCategories`, five fixed labels ('An animal', 'A food',
// 'Something in this room', 'A job', 'A place to go'), each with its own
// curated answer bank (100 secrets total across the five). There is no
// `TextField` anywhere on this screen — the keeper never types a secret,
// they tap a category and the app deals one from its curated list, the same
// "curated category, curated bank" shape `game_two_truths.dart` converged
// on independently for its own safe-content mechanism.
//
// What this screen deliberately does NOT try to do: understand the actual
// yes/no QUESTIONS asked out loud. That would require either free text (the
// exact risk this whole batch exists to avoid) or a natural-language
// engine this codebase doesn't have and shouldn't fake. Instead the app's
// job is narrower and honest about it: track how many questions have been
// asked, and let either person tap 'Yes' or 'No' after each one is asked
// out loud — never asking anyone to type or record the question itself,
// only its curated yes/no answer. That tap does double duty as the
// question tally AND a real per-round history log ("Q1: Yes", "Q2: No",
// ...), which is what the spec's own device-adaptive note for this
// activity ("the running question log alongside the input, so neither of
// you has to remember what's already been asked") actually needed — a log
// of ANSWERS, since the questions themselves were never captured or
// capturable without reopening the free-text risk.
//
// The secret is shown only to whoever is currently 'the keeper' (swappable
// any time via the same actor toggle `game_guess_doodle.dart`'s artist
// switch and `game_two_truths.dart`'s presenter switch both use — "keep
// this facing you," the same honor-system convention those files already
// rely on for local pass-and-play). Twenty questions is a nominal target,
// not a hard cutoff — MASTERFILE §9.2/P2 forbids a punitive "you failed"
// state, so passing 20 shows one gentle, dismissible note and nothing
// blocks asking more. The outcome ("they guessed it" / "reveal the secret")
// is the same soft, never-tallied shape `game_guess_doodle.dart`'s
// `_revealed`/`_gotIt` already use.
import 'dart:math';

import 'package:flutter/material.dart';
import 'game_curated_activity.dart';

// ============================================================ secret bank ==
// Real, drafted content — not a placeholder. Five categories, twenty
// secrets each (100 total), reviewed for tone: genuinely guessable and fun
// for a five-year-old, nothing obscure.

class TwentyQuestionsCategory {
  const TwentyQuestionsCategory(this.id, this.label, this.answers);
  final String id;
  final String label;
  final List<String> answers;
}

const List<TwentyQuestionsCategory> twentyQuestionsCategories = <TwentyQuestionsCategory>[
  TwentyQuestionsCategory('animal', 'An animal', <String>[
    'Dog', 'Cat', 'Elephant', 'Lion', 'Giraffe', 'Penguin', 'Kangaroo', 'Dolphin',
    'Owl', 'Fox', 'Rabbit', 'Turtle', 'Horse', 'Panda', 'Zebra', 'Octopus',
    'Bee', 'Butterfly', 'Frog', 'Squirrel',
  ]),
  TwentyQuestionsCategory('food', 'A food', <String>[
    'Pizza', 'Banana', 'Ice cream', 'Watermelon', 'Popcorn', 'Pancakes', 'Taco',
    'Donut', 'Cookie', 'Sandwich', 'Spaghetti', 'Cheese', 'Strawberry', 'Broccoli',
    'Carrot', 'Hot dog', 'Waffle', 'Soup', 'Pretzel', 'Grapes',
  ]),
  TwentyQuestionsCategory('room', 'Something in this room', <String>[
    'Chair', 'Table', 'Lamp', 'Window', 'Pillow', 'Blanket', 'Backpack', 'Book',
    'Remote control', 'Clock', 'Mirror', 'Rug', 'Shoe', 'Cup', 'Toy box',
    'Picture frame', 'Phone', 'Plant', 'Trash can', 'Light switch',
  ]),
  TwentyQuestionsCategory('job', 'A job', <String>[
    'Doctor', 'Teacher', 'Firefighter', 'Police officer', 'Chef', 'Astronaut',
    'Farmer', 'Artist', 'Veterinarian', 'Pilot', 'Zookeeper', 'Dentist',
    'Librarian', 'Mail carrier', 'Musician', 'Scientist', 'Builder', 'Baker',
    'Photographer', 'Gardener',
  ]),
  TwentyQuestionsCategory('place', 'A place to go', <String>[
    'Beach', 'Zoo', 'Library', 'Park', 'Museum', 'Aquarium', 'Mountain', 'Farm',
    'Amusement park', 'Playground', 'Forest', 'Movie theater', 'Bakery',
    'Swimming pool', 'Campground', 'Ice rink', 'Botanical garden',
    'Science center', 'Lake', 'Bowling alley',
  ]),
];

TwentyQuestionsCategory categoryById(String id) =>
    twentyQuestionsCategories.firstWhere((TwentyQuestionsCategory c) => c.id == id);

/// A soft nudge only — never a hard stop. MASTERFILE §9.2/P2 forbids a
/// punitive cutoff, so nothing in this file ever blocks asking a 21st
/// question.
const int twentyQuestionsTarget = 20;

// ================================================================ engine ===

class QuestionAnswer {
  const QuestionAnswer(this.n, this.yes);
  final int n;
  final bool yes;
}

class TwentyQuestionsRound {
  const TwentyQuestionsRound({
    required this.categoryId,
    required this.secret,
    required this.log,
    this.revealed = false,
    this.gotIt = false,
  });
  final String categoryId;
  final String secret;
  final List<QuestionAnswer> log;
  final bool revealed;
  final bool gotIt;

  int get questionsAsked => log.length;

  TwentyQuestionsRound withAnswer(bool yes) {
    if (revealed) return this;
    return TwentyQuestionsRound(
      categoryId: categoryId,
      secret: secret,
      log: <QuestionAnswer>[...log, QuestionAnswer(log.length + 1, yes)],
    );
  }

  TwentyQuestionsRound withReveal({required bool gotIt}) =>
      TwentyQuestionsRound(categoryId: categoryId, secret: secret, log: log, revealed: true, gotIt: gotIt);
}

TwentyQuestionsRound newRound(TwentyQuestionsCategory category, Random random) => TwentyQuestionsRound(
      categoryId: category.id,
      secret: category.answers[random.nextInt(category.answers.length)],
      log: const <QuestionAnswer>[],
    );

// ================================================================ widget ===

class TwentyQuestionsScreen extends StatefulWidget {
  const TwentyQuestionsScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad', this.random});
  final String childName;
  final String parentName;

  /// Injectable for tests only, matching `game_guess_doodle.dart`'s own
  /// convention — production always uses a real, unseeded Random().
  final Random? random;

  @override
  State<TwentyQuestionsScreen> createState() => _TwentyQuestionsScreenState();
}

class _TwentyQuestionsScreenState extends State<TwentyQuestionsScreen> {
  late final Random _random = widget.random ?? Random();
  TwentyQuestionsRound? _round;
  final List<String> _history = <String>[];

  /// 'child' or 'parent' — whoever currently knows the secret. Swappable
  /// any time; not a turn lock, never counted.
  String _keeperId = 'child';

  String _name(String id) => id == 'child' ? widget.childName : widget.parentName;

  void _pickCategory(TwentyQuestionsCategory category) => setState(() {
        _round = newRound(category, _random);
      });

  void _answer(bool yes) {
    final TwentyQuestionsRound? round = _round;
    if (round == null) return;
    setState(() => _round = round.withAnswer(yes));
  }

  void _reveal({required bool gotIt}) {
    final TwentyQuestionsRound? round = _round;
    if (round == null || round.revealed) return;
    setState(() {
      final TwentyQuestionsRound revealed = round.withReveal(gotIt: gotIt);
      _round = revealed;
      // Content only — no outcome judgment, and deliberately the SAME
      // phrasing regardless of `gotIt`. The transient per-round banner
      // ("Nice — it was..." vs "It was...") is allowed softer wording
      // because it resets every round and is never persisted; this list IS
      // persisted for the whole session, so it must never encode whether
      // the guess succeeded — see the file header and the audit-fix
      // CHANGELOG entry that corrected this (P2: "no record" of outcomes).
      _history.add(
        '${categoryById(revealed.categoryId).label}: it was "${revealed.secret}" '
        '— revealed after ${revealed.questionsAsked} question'
        '${revealed.questionsAsked == 1 ? '' : 's'}',
      );
    });
  }

  void _newRound() => setState(() => _round = null);

  List<String> get _liveHistory {
    final TwentyQuestionsRound? round = _round;
    if (round == null || round.log.isEmpty) return _history;
    final List<String> log = <String>[
      for (final QuestionAnswer qa in round.log) 'Q${qa.n}: ${qa.yes ? 'Yes' : 'No'}',
    ];
    return <String>[..._history, ...log];
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TwentyQuestionsRound? round = _round;
    return Scaffold(
      appBar: AppBar(title: const Text('20 questions')),
      body: SafeArea(
        child: CuratedActivityLayout(
          main: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text('Yes, no, and a secret only one of you knows.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Expanded(
                child: round == null
                    ? _CategoryPicker(onPick: _pickCategory)
                    : _RoundView(
                        round: round,
                        keeperId: _keeperId,
                        keeperName: _name(_keeperId),
                        childName: widget.childName,
                        parentName: widget.parentName,
                        categoryLabel: categoryById(round.categoryId).label,
                        onKeeperChanged: (String id) => setState(() => _keeperId = id),
                        onYes: () => _answer(true),
                        onNo: () => _answer(false),
                        onGotIt: () => _reveal(gotIt: true),
                        onRevealSecret: () => _reveal(gotIt: false),
                        onNewRound: _newRound,
                      ),
              ),
            ]),
          ),
          history: SessionHistoryPanel(
            title: 'This round — and before',
            entries: _liveHistory,
            emptyHint: 'Yes/no taps will show up here as you go.',
          ),
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.onPick});
  final ValueChanged<TwentyQuestionsCategory> onPick;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        const Text('Pick a category for the secret:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            key: const Key('categoryList'),
            children: <Widget>[
              for (final TwentyQuestionsCategory category in twentyQuestionsCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.tonal(onPressed: () => onPick(category), child: Text(category.label)),
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
    required this.keeperId,
    required this.keeperName,
    required this.childName,
    required this.parentName,
    required this.categoryLabel,
    required this.onKeeperChanged,
    required this.onYes,
    required this.onNo,
    required this.onGotIt,
    required this.onRevealSecret,
    required this.onNewRound,
  });

  final TwentyQuestionsRound round;
  final String keeperId;
  final String keeperName;
  final String childName;
  final String parentName;
  final String categoryLabel;
  final ValueChanged<String> onKeeperChanged;
  final VoidCallback onYes;
  final VoidCallback onNo;
  final VoidCallback onGotIt;
  final VoidCallback onRevealSecret;
  final VoidCallback onNewRound;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text("Who's keeping the secret?", style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      SegmentedButton<String>(
        style: SegmentedButton.styleFrom(minimumSize: const Size(64, 48)),
        segments: <ButtonSegment<String>>[
          ButtonSegment<String>(value: 'child', label: Text(childName)),
          ButtonSegment<String>(value: 'parent', label: Text(parentName)),
        ],
        selected: <String>{keeperId},
        onSelectionChanged: (Set<String> s) => onKeeperChanged(s.first),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
        child: round.revealed
            ? Text(round.gotIt ? 'Nice — it was "${round.secret}"!' : 'It was "${round.secret}".',
                key: const Key('secretReveal'),
                style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('$categoryLabel — $keeperName knows the secret:',
                    style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer)),
                const SizedBox(height: 2),
                Text(round.secret,
                    key: const Key('secretWord'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: scheme.onTertiaryContainer)),
                const SizedBox(height: 4),
                Text('Keep this part facing you!',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: scheme.onTertiaryContainer)),
              ]),
      ),
      const SizedBox(height: 12),
      Text('${round.questionsAsked} question${round.questionsAsked == 1 ? '' : 's'} asked',
          key: const Key('questionCount'), style: const TextStyle(fontWeight: FontWeight.w600)),
      if (!round.revealed && round.questionsAsked >= twentyQuestionsTarget) ...[
        const SizedBox(height: 4),
        Text("That's $twentyQuestionsTarget! Keep going, or reveal whenever you're ready.",
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
      const SizedBox(height: 12),
      if (!round.revealed) ...[
        Row(children: <Widget>[
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton(onPressed: onYes, child: const Text('Yes')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.tonal(onPressed: onNo, child: const Text('No')),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton.icon(onPressed: onGotIt, icon: const Icon(Icons.celebration_outlined), label: const Text('They guessed it!'))),
        const SizedBox(height: 8),
        SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton(onPressed: onRevealSecret, child: const Text('Reveal the secret'))),
      ] else
        SizedBox(
            width: double.infinity, height: 48,
            child: FilledButton.tonal(onPressed: onNewRound, child: const Text('New round'))),
    ]);
  }
}
