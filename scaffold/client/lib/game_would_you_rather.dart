// OLIVE BRANCH — would you rather. No longer UNVERIFIED — verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — also manually
// built and run via `flutter analyze` / `flutter test` this session;
// CHANGELOG v0.49.61). MASTERFILE §9.2, §8.11.1, P2. Renders MARKUP screen
// 'gamePicker' catalogue entry 'wouldYouRather'.
//
// Play Together Phase 1, Batch B (docs/superpowers/specs/
// 2026-08-20-play-together-phase1-design.md) — second of four
// curated-prompt activities sharing `game_curated_activity.dart`'s layout
// shell. Co-op, minAge 4 — competitive: false, no handicaps, `story`'s exact
// catalogue shape.
//
// Content source: `wouldYouRatherPrompts` is a fixed, in-repo, curated
// constant — 50 pairs, never user-generated, never fetched, never free
// text. No `TextField` anywhere on this screen. Each prompt is a genuinely
// silly, age-appropriate either/or — never a values judgment (nothing about
// who's a better person for picking either option), never scary or gross
// beyond harmless kid-silly (a talking pet, not anything actually
// frightening).
//
// The mechanic (the spec's "both share an answer, no winner"): each round
// shows ONE curated prompt to both players. Whoever's turn it is answers
// first (an actor switch, same shape `game_guess_doodle.dart`'s artist
// toggle uses — swappable any time, never a turn lock), then the other
// answers the SAME prompt. Once both have answered, both answers reveal
// together — never "who picked the better one," because there isn't one;
// P2's "no scoring which answer was better" is structural here, not a UI
// choice: `WouldYouRatherRound` has no concept of a correct answer at all,
// only two independently recorded picks.
import 'dart:math';

import 'package:flutter/material.dart';
import 'game_curated_activity.dart';

// ============================================================ prompt bank ==
// Real, drafted content — not a placeholder. 50 pairs, reviewed for tone:
// silly and warm, never a values judgment, nothing frightening.

class WouldYouRatherPrompt {
  const WouldYouRatherPrompt(this.id, this.optionA, this.optionB);
  final String id;
  final String optionA;
  final String optionB;
}

const List<WouldYouRatherPrompt> wouldYouRatherPrompts = <WouldYouRatherPrompt>[
  WouldYouRatherPrompt('animal-fly', 'have wings and fly everywhere', 'breathe underwater like a fish'),
  WouldYouRatherPrompt('animal-tail', 'have a fluffy tail like a fox', 'have ears like a rabbit'),
  WouldYouRatherPrompt('animal-talk', 'be able to talk to dogs', 'be able to talk to birds'),
  WouldYouRatherPrompt('animal-size', 'be as small as a mouse for a day', 'be as tall as a giraffe for a day'),
  WouldYouRatherPrompt('animal-pet', 'have a pet dragon', 'have a pet unicorn'),
  WouldYouRatherPrompt('food-icecream', 'eat ice cream for breakfast forever', 'eat pizza for dinner forever'),
  WouldYouRatherPrompt('food-rainbow', 'only eat food that is rainbow-colored', 'only eat food shaped like stars'),
  WouldYouRatherPrompt('food-soup', 'have soup that never gets cold', 'have ice cream that never melts'),
  WouldYouRatherPrompt('food-taste', 'have popcorn that tastes like your favorite candy', 'have water that tastes like lemonade'),
  WouldYouRatherPrompt('food-giant', 'eat a cookie as big as a pizza', 'eat a hundred tiny cookies'),
  WouldYouRatherPrompt('power-invisible', 'be invisible whenever you wanted', 'be able to freeze time for one minute'),
  WouldYouRatherPrompt('power-tiny', 'be able to shrink to the size of a bug', 'be able to grow as tall as a house'),
  WouldYouRatherPrompt('power-fly-car', 'have a flying bicycle', 'have a car that drives underwater'),
  WouldYouRatherPrompt('power-animal-language', 'be able to talk to any animal', 'be able to understand every language in the world'),
  WouldYouRatherPrompt('power-jump', 'be able to jump as high as a house', 'be able to run as fast as a cheetah'),
  WouldYouRatherPrompt('power-weather', 'control the weather for a day', 'control what everyone dreams about'),
  WouldYouRatherPrompt('silly-laugh', 'laugh like a hyena every time you were happy', 'sneeze confetti every time you sneezed'),
  WouldYouRatherPrompt('silly-hop', 'have to hop everywhere like a bunny', 'have to walk backward everywhere'),
  WouldYouRatherPrompt('silly-sing', 'have to sing instead of talk for a whole day', 'have to whisper for a whole day'),
  WouldYouRatherPrompt('silly-hiccup', 'hiccup a bubble every time you were excited', 'have hair that changes color when you are excited'),
  WouldYouRatherPrompt('silly-glow', 'glow in the dark', 'sparkle in the sunlight'),
  WouldYouRatherPrompt('place-treehouse', 'live in a treehouse', 'live in a houseboat'),
  WouldYouRatherPrompt('place-castle', 'live in a castle with no TV', 'live in a regular house with every game ever made'),
  WouldYouRatherPrompt('place-space', 'go to space for a week', 'go to the bottom of the ocean for a week'),
  WouldYouRatherPrompt('place-jungle', 'explore a jungle', 'explore a cave full of crystals'),
  WouldYouRatherPrompt('place-cloud', 'have a bedroom in the clouds', 'have a bedroom under the sea'),
  WouldYouRatherPrompt('weather-rain', 'have it rain jellybeans once a month', 'have it snow marshmallows once a month'),
  WouldYouRatherPrompt('weather-warm', 'live somewhere it is always summer', 'live somewhere it is always winter'),
  WouldYouRatherPrompt('weather-rainbow', 'see a double rainbow every day', 'see shooting stars every night'),
  WouldYouRatherPrompt('game-board', 'play the same board game every day for a month', 'play a different new game every single day'),
  WouldYouRatherPrompt('game-outside', 'have recess be an hour longer', 'have lunch be an hour longer'),
  WouldYouRatherPrompt('game-team', 'always be the team captain', 'always get to pick the game'),
  WouldYouRatherPrompt('school-subject', 'have art class every day', 'have gym class every day'),
  WouldYouRatherPrompt('school-pet', 'bring a pet elephant to school for a day', 'bring a pet penguin to school for a day'),
  WouldYouRatherPrompt('house-slide', 'have a slide instead of stairs at home', 'have a trampoline instead of a bed'),
  WouldYouRatherPrompt('house-color', 'have a purple house', 'have a house shaped like a giant shoe'),
  WouldYouRatherPrompt('house-pool', 'have a swimming pool full of pudding', 'have a bathtub full of warm hot chocolate'),
  WouldYouRatherPrompt('travel-car', 'travel everywhere by hot air balloon', 'travel everywhere by submarine'),
  WouldYouRatherPrompt('travel-train', 'ride a train made of candy', 'ride a rollercoaster made of ice'),
  WouldYouRatherPrompt('silly-nose', 'have a nose that honks like a horn', 'have feet that squeak like a toy'),
  WouldYouRatherPrompt('silly-cape', 'wear a cape everywhere you go', 'wear a crown everywhere you go'),
  WouldYouRatherPrompt('silly-shoes', 'have shoes that never untie', 'have socks that never get holes'),
  WouldYouRatherPrompt('animal-race', 'race a cheetah', 'race a dolphin'),
  WouldYouRatherPrompt('animal-costume', 'dress up as a dinosaur for a whole week', 'dress up as a superhero for a whole week'),
  WouldYouRatherPrompt('story-hero', 'be the hero in a pirate story', 'be the hero in a space story'),
  WouldYouRatherPrompt('story-friend', 'have a talking teddy bear as a best friend', 'have a talking robot as a best friend'),
  WouldYouRatherPrompt('season-snow', 'build the biggest snowman ever', 'build the biggest sandcastle ever'),
  WouldYouRatherPrompt('season-leaves', 'jump in a giant pile of leaves', 'jump in a giant pile of pillows'),
  WouldYouRatherPrompt('sound-music', 'have music play every time you walked', 'have sparkles appear every time you clapped'),
  WouldYouRatherPrompt('dream-fly', 'be able to fly in your dreams every night', 'be able to visit anywhere in the world in your dreams every night'),
];

// ================================================================ engine ===

class WouldYouRatherRound {
  const WouldYouRatherRound({required this.prompt, this.childPick, this.parentPick});
  final WouldYouRatherPrompt prompt;

  /// 'A' or 'B', or null before that person has answered.
  final String? childPick;
  final String? parentPick;

  bool get bothAnswered => childPick != null && parentPick != null;

  String? pickFor(String actorId) => actorId == 'child' ? childPick : parentPick;

  WouldYouRatherRound answeredBy(String actorId, String pick) => WouldYouRatherRound(
        prompt: prompt,
        childPick: actorId == 'child' ? pick : childPick,
        parentPick: actorId == 'parent' ? pick : parentPick,
      );
}

WouldYouRatherRound newRound(Random random, {String? excludingId}) {
  WouldYouRatherPrompt prompt;
  if (wouldYouRatherPrompts.length <= 1) {
    prompt = wouldYouRatherPrompts.first;
  } else {
    do {
      prompt = wouldYouRatherPrompts[random.nextInt(wouldYouRatherPrompts.length)];
    } while (prompt.id == excludingId);
  }
  return WouldYouRatherRound(prompt: prompt);
}

// ================================================================ widget ===

class WouldYouRatherScreen extends StatefulWidget {
  const WouldYouRatherScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad', this.random});
  final String childName;
  final String parentName;

  /// Injectable for tests only, matching `game_guess_doodle.dart`'s own
  /// convention — production always uses a real, unseeded Random().
  final Random? random;

  @override
  State<WouldYouRatherScreen> createState() => _WouldYouRatherScreenState();
}

class _WouldYouRatherScreenState extends State<WouldYouRatherScreen> {
  late final Random _random = widget.random ?? Random();
  late WouldYouRatherRound _round = newRound(_random);
  final List<String> _history = <String>[];

  /// Whose turn it currently is to answer — the next un-answered actor.
  /// Swappable any time via the segmented control, never a turn lock,
  /// matching `game_guess_doodle.dart`'s artist toggle.
  String _answeringId = 'child';

  String _name(String id) => id == 'child' ? widget.childName : widget.parentName;

  void _answer(String pick) {
    setState(() {
      _round = _round.answeredBy(_answeringId, pick);
      if (_round.bothAnswered) {
        _history.add(
          '${_round.prompt.optionA} vs ${_round.prompt.optionB} — '
          '${widget.childName}: ${_round.childPick == 'A' ? _round.prompt.optionA : _round.prompt.optionB}, '
          '${widget.parentName}: ${_round.parentPick == 'A' ? _round.prompt.optionA : _round.prompt.optionB}',
        );
      } else {
        _answeringId = _answeringId == 'child' ? 'parent' : 'child';
      }
    });
  }

  void _nextPrompt() => setState(() {
        _round = newRound(_random, excludingId: _round.prompt.id);
        _answeringId = 'child';
      });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Would you rather')),
      body: SafeArea(
        child: CuratedActivityLayout(
          main: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text('Impossible choices, no wrong answers.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              if (!_round.bothAnswered) ...[
                _TurnBanner(name: _name(_answeringId)),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: _round.bothAnswered
                    ? _RevealCard(
                        round: _round,
                        childName: widget.childName,
                        parentName: widget.parentName,
                        onNext: _nextPrompt,
                      )
                    : _ChoiceCard(round: _round, onPick: _answer),
              ),
            ]),
          ),
          history: SessionHistoryPanel(
            title: 'Would you rather — so far',
            entries: _history,
            emptyHint: 'Your first answered pair will show up here.',
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
        Icon(Icons.compare_arrows_rounded, size: 18, color: scheme.onSecondaryContainer),
        const SizedBox(width: 8),
        Flexible(
          child: Text("$name's turn to answer",
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer)),
        ),
      ]),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.round, required this.onPick});
  final WouldYouRatherRound round;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      const Text('Would you rather...', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 12),
      Expanded(
        child: _OptionButton(
          key: const Key('optionA'),
          label: round.prompt.optionA,
          color: scheme.primaryContainer,
          onColor: scheme.onPrimaryContainer,
          onTap: () => onPick('A'),
        ),
      ),
      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('...or...', textAlign: TextAlign.center)),
      Expanded(
        child: _OptionButton(
          key: const Key('optionB'),
          label: round.prompt.optionB,
          color: scheme.tertiaryContainer,
          onColor: scheme.onTertiaryContainer,
          onTap: () => onPick('B'),
        ),
      ),
    ]);
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({super.key, required this.label, required this.color, required this.onColor, required this.onTap});
  final String label;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: onColor)),
            ),
          ),
        ),
      );
}

class _RevealCard extends StatelessWidget {
  const _RevealCard({required this.round, required this.childName, required this.parentName, required this.onNext});
  final WouldYouRatherRound round;
  final String childName;
  final String parentName;
  final VoidCallback onNext;

  String _label(String pick) => pick == 'A' ? round.prompt.optionA : round.prompt.optionB;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Container(
        key: const Key('revealCard'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('$childName picked: ${_label(round.childPick!)}',
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer)),
          const SizedBox(height: 8),
          Text('$parentName picked: ${_label(round.parentPick!)}',
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer)),
        ]),
      ),
      const Spacer(),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.tonal(onPressed: onNext, child: const Text('Next question')),
      ),
    ]);
  }
}
