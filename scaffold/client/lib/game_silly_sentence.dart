// OLIVE BRANCH — silly sentence maker. Verified by CI (a Flutter toolchain
// now runs for real in tools/verify.sh's automated pipeline — also manually
// built and run via `flutter analyze` / `flutter test` this session;
// CHANGELOG v0.49.61). MASTERFILE §9.2, §8.11.1, P2. Renders MARKUP screen
// 'gamePicker' catalogue entry 'sillySentence'.
//
// Play Together Phase 1, Batch B (docs/superpowers/specs/
// 2026-08-20-play-together-phase1-design.md) — the first of four
// curated-prompt activities sharing `game_curated_activity.dart`'s layout
// shell (see that file's own header for why a small shared base is worth it
// here). Co-op, minAge 4 (game_logic.dart's catalogue) — competitive: false,
// no handicaps, `story`'s exact catalogue shape: nothing to be behind at.
//
// Content source (the actual safety mechanism, per the spec's "Content
// strategy" section): every word below is a fixed, in-repo, curated
// constant — never user-generated, never fetched, never free text. There is
// no `TextField` anywhere on this screen. Mad-libs-style: a curated
// sentence [SentenceTemplate] always leads with a 'silly character' blank
// (kept first in every template so the phrase's own capital letter never
// lands mid-sentence — a small grammar choice, not an accident), then fills
// in a curated 'unlikely place', 'ridiculous action', and/or 'silly reason'
// blank. 80 words across four categories (20 each) — real, drafted content
// matching `guessDoodleWords`' depth as the quality bar, not a placeholder.
// Each turn presents FOUR random options from the current blank's category
// (never the full list at once — a five-year-old choosing from four things
// is a real choice; choosing from twenty is a scroll), so the player still
// actively picks the word, just never types one.
//
// Turn-taking: the 'silly character' blank (always first) starts with
// 'child', exactly matching `game_story.dart`'s "the CHILD starts" — every
// blank after that alternates strictly, mirroring `game_story.dart`'s
// addLine() turn flip. Reveal is the sentence read aloud (text on screen,
// not actual TTS — no audio infra exists for this, matching the spec's own
// "text on screen, not actual TTS" note). Nothing here is scored: a
// finished sentence just joins the session history panel at wide postures,
// never tallied, never ranked against a previous one.
import 'dart:math';

import 'package:flutter/material.dart';
import 'game_curated_activity.dart';

// ============================================================ word bank ====
// Real, drafted content — not a placeholder. Every blank in every template
// draws from exactly one of these four categories; see the templates below
// for how they combine.

const List<String> sillyCharacters = <String>[
  'A giggling grandma', 'A sleepy dragon', 'A wobbly robot', 'A tiny dinosaur',
  'Our silliest cousin', 'A superhero in pajamas', 'A very serious cat',
  'A grumpy wizard', 'A ticklish octopus', 'A polka-dot penguin',
  'A mischievous fairy', 'A snoring superhero', 'A bouncing kangaroo',
  'A shy monster', 'A dancing skeleton', 'A confused astronaut',
  'A tiny dragon in rain boots', 'A brave baby bunny', 'A grumpy pirate',
  'A sneaky ninja hamster',
];

const List<String> unlikelyPlaces = <String>[
  'to the moon', 'into the bathtub', 'under the kitchen table',
  'to school in their pajamas', 'into a giant bowl of spaghetti',
  'to the top of a mountain of pillows', 'into outer space',
  "to grandma's garden", 'into a bubble bath the size of a swimming pool',
  'to the bottom of the ocean', 'into the freezer',
  'to a birthday party for ants', 'into a cardboard box castle',
  'to the middle of a thunderstorm', 'into a pile of crunchy autumn leaves',
  'to a tea party in the treehouse', 'into the washing machine',
  'to a disco on the ceiling', 'into a giant sandbox',
  'to the very back of a sock drawer',
];

const List<String> ridiculousActions = <String>[
  'started singing opera', 'did the chicken dance',
  'sneezed so hard they flew backward', 'fell asleep standing up',
  'turned into wobbly jelly', 'started speaking in rhymes',
  'began juggling jellybeans', 'did fifty somersaults in a row',
  'started tap-dancing', 'burped the entire alphabet',
  'grew a very long, curly mustache', 'started painting everything purple',
  'hiccupped so loud the windows rattled', 'puffed up like a giant marshmallow',
  'started riding a unicycle', 'began telling knock-knock jokes to a lamp',
  'did a very wobbly cartwheel', 'started meowing instead of talking',
  'tried to hug a very prickly cactus', 'began floating slowly up to the ceiling',
];

const List<String> sillyReasons = <String>[
  'because the moon told them to', 'just to see what would happen',
  'because a squirrel dared them', 'to win a very silly contest',
  'because their socks felt lucky today', 'for absolutely no reason at all',
  'because it was a Tuesday', 'to impress a very unimpressed cat',
  'because they forgot how not to', 'just because it felt right',
  'to break the world record for silliness', 'because a talking sandwich asked nicely',
  'for the fun of it', 'because the wind whispered a secret',
  'to make absolutely everyone laugh', 'because their tummy told them to',
  'just to feel the breeze', 'because a wizard sneezed nearby',
  'to see the world upside down', "because that's simply what Tuesdays are for",
];

/// Category key -> its curated word list. Every template blank names one of
/// these keys; `_pickOptions` is the only place this map is read.
const Map<String, List<String>> sentenceWordCategories = <String, List<String>>{
  'character': sillyCharacters,
  'place': unlikelyPlaces,
  'action': ridiculousActions,
  'reason': sillyReasons,
};

/// A curated sentence shape. `categories.length == textParts.length - 1`;
/// the finished sentence interleaves `textParts` around one filled word per
/// category, in order. Every template's first category is 'character' and
/// first textPart is '' — see the file header on why capitalization stays
/// clean this way.
class SentenceTemplate {
  const SentenceTemplate({required this.id, required this.textParts, required this.categories});
  final String id;
  final List<String> textParts;
  final List<String> categories;
}

const List<SentenceTemplate> sentenceTemplates = <SentenceTemplate>[
  SentenceTemplate(
    id: 'wentAnd',
    textParts: <String>['', ' went ', ' and ', ', ', '.'],
    categories: <String>['character', 'place', 'action', 'reason'],
  ),
  SentenceTemplate(
    id: 'decidedTo',
    textParts: <String>['', ' decided to go ', '. Then they ', ' — ', '!'],
    categories: <String>['character', 'place', 'action', 'reason'],
  ),
  SentenceTemplate(
    id: 'snuckSuddenly',
    textParts: <String>['', ' snuck ', ', and suddenly ', '.'],
    categories: <String>['character', 'place', 'action'],
  ),
  SentenceTemplate(
    id: 'allBecause',
    textParts: <String>['', ' ', ', all ', '.'],
    categories: <String>['character', 'action', 'reason'],
  ),
  SentenceTemplate(
    id: 'believeItOrNot',
    textParts: <String>['', ', believe it or not, ', ' — ', ', and then ran off ', '.'],
    categories: <String>['character', 'action', 'reason', 'place'],
  ),
];

// ================================================================ engine ===

class SentenceBlank {
  const SentenceBlank({required this.category, this.filledWith});
  final String category;
  final String? filledWith;

  SentenceBlank fill(String word) => SentenceBlank(category: category, filledWith: word);
}

class SentenceRound {
  const SentenceRound({required this.templateId, required this.textParts, required this.blanks, required this.turnIndex});
  final String templateId;
  final List<String> textParts;
  final List<SentenceBlank> blanks;

  /// Index of the next blank to fill; `== blanks.length` once the sentence
  /// is complete.
  final int turnIndex;

  bool get complete => turnIndex >= blanks.length;

  /// The 'silly character' blank (always index 0) starts with 'child',
  /// matching `game_story.dart`'s "the CHILD starts"; every blank after
  /// that alternates strictly.
  String get currentTurnActorId => turnIndex.isEven ? 'child' : 'parent';

  String get currentCategory => blanks[turnIndex].category;
}

SentenceRound newRound(Random random, {String? excludingTemplateId}) {
  SentenceTemplate template;
  if (sentenceTemplates.length <= 1) {
    template = sentenceTemplates.first;
  } else {
    do {
      template = sentenceTemplates[random.nextInt(sentenceTemplates.length)];
    } while (template.id == excludingTemplateId);
  }
  return SentenceRound(
    templateId: template.id,
    textParts: template.textParts,
    blanks: <SentenceBlank>[for (final String c in template.categories) SentenceBlank(category: c)],
    turnIndex: 0,
  );
}

/// Four random, non-repeating options from the CURRENT blank's category —
/// a real choice for a five-year-old, not a scroll through twenty words.
List<String> optionsFor(SentenceRound round, Random random, {int count = 4}) {
  final List<String> words = List<String>.of(sentenceWordCategories[round.currentCategory]!)..shuffle(random);
  return words.take(count).toList();
}

SentenceRound fillBlank(SentenceRound round, String word) {
  if (round.complete) return round;
  final List<SentenceBlank> blanks = List<SentenceBlank>.of(round.blanks);
  blanks[round.turnIndex] = blanks[round.turnIndex].fill(word);
  return SentenceRound(templateId: round.templateId, textParts: round.textParts, blanks: blanks, turnIndex: round.turnIndex + 1);
}

/// The finished (or in-progress) sentence text, with `___` standing in for
/// any blank not yet filled.
String sentenceText(SentenceRound round) {
  final StringBuffer buffer = StringBuffer(round.textParts.first);
  for (int i = 0; i < round.blanks.length; i++) {
    buffer.write(round.blanks[i].filledWith ?? '___');
    buffer.write(round.textParts[i + 1]);
  }
  return buffer.toString();
}

// ================================================================ widget ===

class SillySentenceScreen extends StatefulWidget {
  const SillySentenceScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad', this.random});
  final String childName;
  final String parentName;

  /// Injectable for tests only, matching `game_guess_doodle.dart`'s own
  /// convention — production always uses a real, unseeded Random().
  final Random? random;

  @override
  State<SillySentenceScreen> createState() => _SillySentenceScreenState();
}

class _SillySentenceScreenState extends State<SillySentenceScreen> {
  late final Random _random = widget.random ?? Random();
  late SentenceRound _round = newRound(_random);
  late List<String> _options = optionsFor(_round, _random);
  final List<String> _history = <String>[];

  String _actorName(String id) => id == 'child' ? widget.childName : widget.parentName;

  void _pick(String word) {
    setState(() {
      _round = fillBlank(_round, word);
      if (_round.complete) {
        _history.add(sentenceText(_round));
      } else {
        _options = optionsFor(_round, _random);
      }
    });
  }

  void _newSentence() => setState(() {
        _round = newRound(_random, excludingTemplateId: _round.templateId);
        _options = optionsFor(_round, _random);
      });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Silly sentence maker')),
      body: SafeArea(
        child: CuratedActivityLayout(
          main: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Build the silliest sentence you can, one word at a time.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Container(
                key: const Key('sentenceCard'),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
                child: Text(sentenceText(_round),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer)),
              ),
              const SizedBox(height: 16),
              if (!_round.complete) ...[
                _TurnBanner(name: _actorName(_round.currentTurnActorId)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    key: const Key('wordOptions'),
                    children: <Widget>[
                      for (final String option in _options)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton(onPressed: () => _pick(option), child: Text(option, textAlign: TextAlign.center)),
                          ),
                        ),
                    ],
                  ),
                ),
              ] else ...[
                Row(children: <Widget>[
                  Icon(Icons.celebration_outlined, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Read it aloud!', style: TextStyle(fontWeight: FontWeight.w700))),
                ]),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.tonal(onPressed: _newSentence, child: const Text('Make another one')),
                ),
              ],
            ]),
          ),
          history: SessionHistoryPanel(
            title: 'Sentences so far',
            entries: _history,
            emptyHint: 'Your first finished sentence will show up here.',
          ),
        ),
      ),
    );
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(Icons.emoji_emotions_outlined, size: 18, color: scheme.onSecondaryContainer),
        const SizedBox(width: 8),
        Flexible(
          child: Text("$name's turn to pick a word",
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer)),
        ),
      ]),
    );
  }
}
