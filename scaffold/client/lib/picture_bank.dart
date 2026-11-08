// OLIVE BRANCH — picture-first input: a small bank of pictures with labels that a
// child who cannot type yet can tap instead. No longer UNVERIFIED — verified by CI
// (client/test/picture_bank_test.dart). MASTERFILE §8.4 (pre-readers), P2, P4.
//
// ADDITIVE. Typing still works exactly as before; a picture is a second way to
// say the same thing, and what it adds is plain words (the picture's label), the
// same words typing would have added. Nothing about HOW something was entered is
// stored or shown.
//
// P2: nothing here counts, ranks or rewards. P4: no bank carries a price, a
// brand, a shop or a link; a "want" is a kind of thing, not a product.
//
// Every picture has a label that is both what a screen reader says and what
// long-press reads aloud, so the bank is usable by a child who can neither read
// nor see it well. Each tile clears the child's touch floor (64dp, 80 with
// "larger targets").
import 'package:flutter/material.dart';

import 'access_scope.dart';
import 'read_aloud.dart';

class PictureChoice {
  const PictureChoice(this.id, this.icon, this.label, {this.sentence});
  final String id;
  final IconData icon;

  /// Plain words: the screen-reader name, the spoken name, and what typing
  /// this would have entered.
  final String label;

  /// For a journal page: a first-person line the picture writes. Null when the
  /// label is used as is.
  final String? sentence;
}

/// Kinds of thing she might want. Never a product, a brand or a price (P4).
const List<PictureChoice> wantsPictureBank = <PictureChoice>[
  PictureChoice('toy', Icons.toys_outlined, 'A toy'),
  PictureChoice('game', Icons.sports_esports_outlined, 'A game'),
  PictureChoice('book', Icons.menu_book_outlined, 'A book'),
  PictureChoice('ball', Icons.sports_soccer_outlined, 'A ball'),
  PictureChoice('bike', Icons.pedal_bike_outlined, 'A bicycle'),
  PictureChoice('art', Icons.palette_outlined, 'Art things'),
  PictureChoice('music', Icons.music_note_outlined, 'Music'),
  PictureChoice('pet', Icons.pets_outlined, 'A pet'),
  PictureChoice('treat', Icons.icecream_outlined, 'A treat'),
  PictureChoice('outing', Icons.park_outlined, 'A day out'),
];

/// Kinds of thing she might need.
const List<PictureChoice> needsPictureBank = <PictureChoice>[
  PictureChoice('shoes', Icons.hiking_outlined, 'Shoes'),
  PictureChoice('coat', Icons.checkroom_outlined, 'A coat'),
  PictureChoice('food', Icons.restaurant_outlined, 'Food'),
  PictureChoice('drink', Icons.water_drop_outlined, 'A drink'),
  PictureChoice('school', Icons.backpack_outlined, 'School things'),
  PictureChoice('sleep', Icons.bedtime_outlined, 'Sleep'),
  PictureChoice('medicine', Icons.medication_outlined, 'My medicine'),
  PictureChoice('glasses', Icons.visibility_outlined, 'My glasses'),
  PictureChoice('wash', Icons.clean_hands_outlined, 'To get clean'),
  PictureChoice('hug', Icons.favorite_border, 'A hug'),
];

/// How she feels. Each writes one plain sentence into her page.
const List<PictureChoice> journalFeelingsBank = <PictureChoice>[
  PictureChoice('happy', Icons.sentiment_satisfied_alt_outlined, 'Happy', sentence: 'I feel happy.'),
  PictureChoice('sad', Icons.sentiment_dissatisfied_outlined, 'Sad', sentence: 'I feel sad.'),
  PictureChoice('cross', Icons.mood_bad_outlined, 'Cross', sentence: 'I feel cross.'),
  PictureChoice('tired', Icons.bedtime_outlined, 'Tired', sentence: 'I feel tired.'),
  PictureChoice('scared', Icons.sentiment_very_dissatisfied_outlined, 'Scared', sentence: 'I feel scared.'),
  PictureChoice('silly', Icons.sentiment_very_satisfied_outlined, 'Silly', sentence: 'I feel silly.'),
  PictureChoice('loved', Icons.favorite_border, 'Loved', sentence: 'I feel loved.'),
  PictureChoice('quiet', Icons.spa_outlined, 'Quiet', sentence: 'I feel quiet.'),
];

/// What her day held, in a few pictures.
const List<PictureChoice> journalMomentsBank = <PictureChoice>[
  PictureChoice('played', Icons.sports_esports_outlined, 'Played', sentence: 'I played today.'),
  PictureChoice('friend', Icons.people_outline, 'A friend', sentence: 'I saw a friend today.'),
  PictureChoice('school', Icons.backpack_outlined, 'School', sentence: 'I was at school today.'),
  PictureChoice('outside', Icons.park_outlined, 'Outside', sentence: 'I went outside today.'),
  PictureChoice('ate', Icons.restaurant_outlined, 'Food', sentence: 'I had something nice to eat.'),
  PictureChoice('made', Icons.palette_outlined, 'Made something', sentence: 'I made something today.'),
  PictureChoice('family', Icons.home_outlined, 'Family', sentence: 'I was with my family.'),
  PictureChoice('missed', Icons.favorite_outline, 'Missing someone', sentence: 'I missed someone today.'),
];

/// The words a picture adds to a page or a list: its sentence if it has one,
/// else its label. Pure, so a test can hold the "same words typing would have
/// entered" rule.
String wordsFor(PictureChoice c) => c.sentence ?? c.label;

/// A wrap of tappable pictures. [onPick] gets the choice she tapped; nothing is
/// counted, and picking the same picture twice is the caller's to handle quietly.
class PictureBank extends StatelessWidget {
  const PictureBank({super.key, required this.choices, required this.onPick, this.heading});
  final List<PictureChoice> choices;
  final ValueChanged<PictureChoice> onPick;

  /// A short line above the pictures (also given to a screen reader as the
  /// group's name).
  final String? heading;

  @override
  Widget build(BuildContext context) {
    final double floor = childTargetOf(context);
    final Widget wrap = Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
      for (final PictureChoice c in choices) PictureTile(choice: c, floor: floor, onTap: () => onPick(c)),
    ]);
    return Semantics(
      container: true,
      label: heading,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        if (heading != null) Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ExcludeSemantics(child: Text(heading!, style: Theme.of(context).textTheme.labelLarge))),
        wrap,
      ]),
    );
  }
}

class PictureTile extends StatelessWidget {
  const PictureTile({super.key, required this.choice, required this.floor, required this.onTap});
  final PictureChoice choice;
  final double floor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: choice.label,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: () => speakOnLongPress(context, choice.label),
      child: InkWell(
        key: Key('picture_${choice.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: () => speakOnLongPress(context, choice.label),
        child: Container(
          constraints: BoxConstraints(minWidth: floor + 8, minHeight: floor + 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
              color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(choice.icon, size: 30, color: scheme.onSecondaryContainer),
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(choice.label, textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer)),
            ),
          ]),
        ),
      ),
    );
  }
}
