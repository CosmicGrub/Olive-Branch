// OLIVE BRANCH — the guided first run, THE SCRIPT AS DATA. MASTERFILE §8.5.14.
//
// This table IS docs/planning/ONBOARDING-SCRIPT.md in code: client/test/guided_script_doc_test.dart reads that file and
// fails if an id, a slot, a version, a kind, a strip position, a title, the words, an icon label or an action differs.
// One script, two halves (the grown-up's on the phone, hers on the tablet). The engine (guided_engine.dart) and the
// screens (guided_*.dart) read ONLY this table plus whatever later features register in guided_registry.dart; nothing
// here is a screen.
//
// Words in curly braces are filled in at render time: {name} is her first name, or "her" when there is none.
import 'package:flutter/material.dart';

import 'child_home_bands.dart' show BandTile, kBandTiles;
import 'child_home_bands_ui.dart' show bandIcon;

/// Raised by one every time the script gains an entry (extension step 3 in the script document).
const int kGuidedScriptVersion = 1;

enum GuidedHalf { adult, child }

/// What the five controls do on a step (the "Kinds of step" table in the script document).
enum GuidedKind {
  info('info'),
  form('form'),
  defaultChoice('default'),
  task('task'),
  coach('coach'),
  end('end'),
  childCard('childcard'),

  /// Not a step: an icon label a later feature adds to her "And there is more" card.
  childLabel('childlabel');

  const GuidedKind(this.word);
  final String word;
}

/// The slots, in order. A slot is a named place in the script; an entry registers into one.
const List<String> kGuidedSlots = <String>[
  'adult.welcome',
  'adult.setup',
  'adult.tablet',
  'adult.tour.core',
  'adult.tour.features',
  'adult.tour.close',
  'adult.help',
  'adult.done',
  'child.welcome',
  'child.icons',
  'child.extra',
  'child.close',
];

/// One icon with its label spelled out: never an icon alone.
class GuidedLabel {
  const GuidedLabel(this.icon, this.label, this.line);
  final IconData icon;
  final String label;

  /// One short friendly line under the label ('' = none).
  final String line;
}

class GuidedEntry {
  const GuidedEntry({
    required this.id,
    required this.half,
    required this.slot,
    required this.kind,
    required this.title,
    required this.words,
    this.phase = '',
    this.since = 1,
    this.needsFeature,
    this.labels = const <GuidedLabel>[],
    this.action = 'Next',
    this.anchor,
    this.whatsNew = false,
    this.sees = '',
  });

  final String id;
  final GuidedHalf half;

  /// A name from [kGuidedSlots].
  final String slot;
  final GuidedKind kind;

  /// The strip group of a grown-up step: steps sharing a phase share one "Step n of N" number (the tour stops).
  final String phase;

  /// The script version this entry first shipped in. An entry from a version this build does not know is ignored.
  final int since;

  /// A feature flag that must be on for this entry to show; null = always. A missing or off feature skips the entry.
  final String? needsFeature;
  final String title;
  final String words;
  final List<GuidedLabel> labels;
  final String action;

  /// The coach-mark anchor id this stop points at ([CoachAnchor]); null = a plain card.
  final String? anchor;

  /// Shown in the "What's new" mini-tour to an install that already finished first run.
  final bool whatsNew;

  /// What the person sees (design note, also in the script document).
  final String sees;

  GuidedEntry withLabels(List<GuidedLabel> l) => GuidedEntry(
      id: id, half: half, slot: slot, kind: kind, title: title, words: words, phase: phase, since: since,
      needsFeature: needsFeature, labels: l, action: action, anchor: anchor, whatsNew: whatsNew, sees: sees);

  /// Title and words with {name} filled in.
  String fill(String s, String? name) =>
      s.replaceAll('{name}', (name == null || name.trim().isEmpty) ? 'her' : name.trim());
}

/// The fixed (non-entry) words of the grown-up half and of hers.
class GuidedWords {
  static const String pauseTitle = 'Take all the time you need.';
  static const String pauseBody = 'Your place is saved. Come back whenever you are ready.';
  static const String pauseButton = 'I am ready';
  static const String tabletWait = "Waiting for {name}'s tablet. Nothing is wrong, and this can take a minute.";
  static const String tabletRecover = 'That did not work, and that is okay. Nothing was shared. Check her tablet is '
      'on the same Wi-Fi, then tap Make a new code and we will try again.';
  static const List<String> tabletSteps = <String>[
    'On this phone, tap Open the window and type your PIN.',
    'On her tablet, tap A grown-up does this.',
    "Then tap I'm the grown-up.",
    'Tap the same picture the tablet shows here.',
    'Pick the cards that match, then say yes.',
  ];
  static const String tabletDone = "{name}'s tablet is connected. Well done.";
  static const String tourNoFind = 'You will find this under More on this screen.';
  static const String later = 'Still waiting for you, whenever you like:';
  static const String tryMessages = 'Nothing here right now. That is just fine.';
  static const String tryColour = 'Lovely.';
}

BandTile _b(String id) => kBandTiles[id]!;
GuidedLabel _band(String id, String line, {String? title}) =>
    GuidedLabel(bandIcon(_b(id).icon), title ?? _b(id).title, line);

/// The script, version 1. Order here is the order a person sees; slots keep later additions in the right place.
final List<GuidedEntry> kBaseGuidedEntries = <GuidedEntry>[
  // ------------------------------------------------------------------ the grown-up half
  const GuidedEntry(
    id: 'a.welcome', half: GuidedHalf.adult, slot: 'adult.welcome', kind: GuidedKind.info, phase: 'welcome',
    sees: 'A calm card with two small pictures',
    title: 'Welcome to Olive',
    words: 'Olive is a calm place for your family to keep messages, care and plans together, and it gives your child '
        'a small, gentle app of her own. Everything stays on this phone, and there is nothing to sign up for.',
    labels: <GuidedLabel>[
      GuidedLabel(Icons.phone_android, 'Your phone', 'For you'),
      GuidedLabel(Icons.tablet_android, 'Her tablet', 'For her'),
    ],
    action: "Let's begin",
  ),
  const GuidedEntry(
    id: 'a.you', half: GuidedHalf.adult, slot: 'adult.setup', kind: GuidedKind.form, phase: 'you',
    sees: 'Two boxes: your name, and what she calls you',
    title: 'About you',
    words: 'First, a little about you. Your name, and what she calls you, like Mom, Dad or your own word. '
        'This stays on this phone.',
    labels: <GuidedLabel>[
      GuidedLabel(Icons.person_outline, 'Your name', 'Only the family sees it'),
      GuidedLabel(Icons.favorite_border, 'What she calls you', 'Mom, Dad or your own word'),
    ],
  ),
  const GuidedEntry(
    id: 'a.her', half: GuidedHalf.adult, slot: 'adult.setup', kind: GuidedKind.form, phase: 'her',
    sees: 'Her first name and a row of ages',
    title: 'About her',
    words: 'Now a little about her. Her first name, and her age. Her age decides what she sees, so please choose '
        'carefully. Changing it later needs your PIN.',
    labels: <GuidedLabel>[
      GuidedLabel(Icons.child_care, 'Her first name', 'How her app greets her'),
      GuidedLabel(Icons.cake_outlined, 'Her age band', 'What her home shows'),
    ],
  ),
  const GuidedEntry(
    id: 'a.zone', half: GuidedHalf.adult, slot: 'adult.setup', kind: GuidedKind.defaultChoice, phase: 'zone',
    sees: 'A short list of time zones',
    title: 'Her clock',
    words: 'Which time zone is she in? Most families choose the first one, the same as this phone.',
    labels: <GuidedLabel>[GuidedLabel(Icons.public, 'Time zone', 'Where her clock is')],
  ),
  const GuidedEntry(
    id: 'a.pin', half: GuidedHalf.adult, slot: 'adult.setup', kind: GuidedKind.form, phase: 'pin',
    sees: 'The PIN keypad',
    title: 'Choose your PIN',
    words: 'This PIN is yours. It guards your settings and her age, and it works with no internet. Pick one you '
        'will remember and she will not guess.',
    labels: <GuidedLabel>[
      GuidedLabel(Icons.dialpad, 'PIN keypad', 'Type the numbers'),
      GuidedLabel(Icons.lock_outline, 'Stays here', 'Never leaves this phone'),
    ],
    action: 'Save PIN and continue',
  ),
  const GuidedEntry(
    id: 'a.tablet', half: GuidedHalf.adult, slot: 'adult.tablet', kind: GuidedKind.task, phase: 'tablet',
    sees: 'A card, then the real connect screens with a helper strip',
    title: 'Connect her tablet',
    words: "Let's connect her tablet now, one small step at a time. Bring her tablet, and make sure it is on the "
        'same Wi-Fi. If you would rather do this later, that is fine.',
    labels: <GuidedLabel>[
      GuidedLabel(Icons.phonelink_lock_outlined, 'Open the window', 'This phone opens a short, private window'),
      GuidedLabel(Icons.tablet_android, 'Her tablet', 'Tap A grown-up does this'),
      GuidedLabel(Icons.touch_app_outlined, 'Same picture', 'Tap the one that matches'),
      GuidedLabel(Icons.fact_check_outlined, 'Match', 'Pick the same cards'),
      GuidedLabel(Icons.check_circle_outline, 'Yes', 'Say yes to connect it'),
    ],
    action: 'Open the connect screen',
  ),
  const GuidedEntry(
    id: 'a.tour.bank', half: GuidedHalf.adult, slot: 'adult.tour.core', kind: GuidedKind.coach, phase: 'tour',
    anchor: 'home.messageBanking', sees: 'Your home, with Message banking lit up',
    title: 'Message banking',
    words: 'Write a message now and choose the right time for it to arrive, so it lands when she is ready, not in '
        'the middle of dinner.',
    labels: <GuidedLabel>[GuidedLabel(Icons.schedule_send, 'Message banking', 'Send at the right time')],
  ),
  const GuidedEntry(
    id: 'a.tour.avail', half: GuidedHalf.adult, slot: 'adult.tour.core', kind: GuidedKind.coach, phase: 'tour',
    anchor: 'home.availability', sees: 'Your home, with Availability lit up',
    title: 'Availability',
    words: 'See when each grown-up can be reached, so nobody has to guess.',
    labels: <GuidedLabel>[GuidedLabel(Icons.event_available, 'Availability', 'When you can be reached')],
  ),
  const GuidedEntry(
    id: 'a.tour.guard', half: GuidedHalf.adult, slot: 'adult.tour.core', kind: GuidedKind.coach, phase: 'tour',
    anchor: 'home.sendTimeGuard', sees: 'Your home, with Send-time guard lit up',
    title: 'Send-time guard',
    words: 'Before you send, Olive checks her clock and tells you if it is her bedtime or school time.',
    labels: <GuidedLabel>[GuidedLabel(Icons.schedule, 'Send-time guard', 'Checks her clock first')],
  ),
  const GuidedEntry(
    id: 'a.tour.care', half: GuidedHalf.adult, slot: 'adult.tour.core', kind: GuidedKind.coach, phase: 'tour',
    anchor: 'home.medsCare', sees: 'Your home, with Meds and care lit up',
    title: 'Meds & care',
    words: "Medicines, expenses and handover notes live together here, so nothing depends on one person's memory.",
    labels: <GuidedLabel>[
      GuidedLabel(Icons.medical_services_outlined, 'Meds & care', 'Medicines, expenses, handover notes'),
    ],
  ),
  const GuidedEntry(
    id: 'a.tour.emergency', half: GuidedHalf.adult, slot: 'adult.tour.core', kind: GuidedKind.coach, phase: 'tour',
    anchor: 'home.emergencyCard', sees: 'Your home, with Emergency card lit up',
    title: 'Emergency card',
    words: 'Her allergies, her doctor and who to call, on one card, ready for anyone who is caring for her.',
    labels: <GuidedLabel>[
      GuidedLabel(Icons.medical_information, 'Emergency card', 'Ready for anyone caring for her'),
    ],
  ),
  const GuidedEntry(
    id: 'a.tour.call', half: GuidedHalf.adult, slot: 'adult.tour.core', kind: GuidedKind.coach, phase: 'tour',
    anchor: 'home.call', sees: 'Your home, with the Call button lit up',
    title: 'Call',
    words: 'Call her from the top of your home. A call needs both of you to have internet.',
    labels: <GuidedLabel>[GuidedLabel(Icons.call_outlined, 'Call', 'Needs internet on both sides')],
  ),
  const GuidedEntry(
    id: 'a.tour.more', half: GuidedHalf.adult, slot: 'adult.tour.close', kind: GuidedKind.coach, phase: 'tour',
    anchor: 'home.more', sees: 'Your home, with More lit up',
    title: 'More',
    words: 'More holds everything else, and Settings is inside it. Nothing here is hidden. It is just tucked away '
        'so the home stays calm.',
    labels: <GuidedLabel>[GuidedLabel(Icons.more_horiz, 'More', 'Everything else, and Settings')],
  ),
  const GuidedEntry(
    id: 'a.tour.her', half: GuidedHalf.adult, slot: 'adult.tour.close', kind: GuidedKind.coach, phase: 'tour',
    anchor: 'home.more', sees: 'Your home, with More lit up again',
    title: 'Her: what she sees',
    words: 'Open More, then Settings, then Her. That is where you choose what she sees and how her app looks.',
    labels: <GuidedLabel>[GuidedLabel(Icons.favorite_border, 'Her', 'What she sees, in Settings')],
  ),
  const GuidedEntry(
    id: 'a.help', half: GuidedHalf.adult, slot: 'adult.help', kind: GuidedKind.info, phase: 'help',
    sees: 'A calm card',
    title: 'Help is close by',
    words: 'You can see this tour again any time. Open More, then Settings, then Learn, and tap Show me around '
        'again. Nothing here can break anything.',
    labels: <GuidedLabel>[
      GuidedLabel(Icons.help_outline, 'Help', 'In Settings, under Learn'),
      GuidedLabel(Icons.replay, 'Show me around again', 'Replays this'),
    ],
  ),
  const GuidedEntry(
    id: 'a.done', half: GuidedHalf.adult, slot: 'adult.done', kind: GuidedKind.end, phase: 'done',
    sees: 'A calm card, and any parts you chose to do later',
    title: 'You are all set',
    words: 'Her home is ready. Take your time with it.',
    labels: <GuidedLabel>[GuidedLabel(Icons.home_outlined, 'Home', 'Where you are going')],
    action: 'Go to my home',
  ),

  // ------------------------------------------------------------------ her half
  const GuidedEntry(
    id: 'c.offer', half: GuidedHalf.child, slot: 'child.welcome', kind: GuidedKind.childCard,
    sees: 'A grown-up and a tablet picture',
    title: 'A grown-up does this',
    words: 'A grown-up will show you around.',
    labels: <GuidedLabel>[GuidedLabel(Icons.escalator_warning_rounded, 'Grown-up', 'Taps here')],
    action: "I'm the grown-up",
  ),
  const GuidedEntry(
    id: 'c.start', half: GuidedHalf.child, slot: 'child.welcome', kind: GuidedKind.childCard,
    sees: "The grown-up's one card, after the grown-up gate",
    title: 'Ready to show {name} around?',
    words: 'This is a short welcome. It shows her the pictures on her home. Hand her the tablet when you are ready. '
        'She cannot start it on her own.',
    action: 'Start her welcome',
  ),
  const GuidedEntry(
    id: 'c.hello', half: GuidedHalf.child, slot: 'child.welcome', kind: GuidedKind.childCard,
    sees: 'A big friendly wave',
    title: 'Hello, {name}!',
    words: "This is your Olive. Let's look at what is on your home.",
    labels: <GuidedLabel>[GuidedLabel(Icons.waving_hand_outlined, 'Hello', 'Say hello')],
  ),
  GuidedEntry(
    id: 'c.day', half: GuidedHalf.child, slot: 'child.icons', kind: GuidedKind.childCard,
    sees: 'Two big icons',
    title: 'My day and Play together',
    words: 'My day shows what comes next. Play together is for games.',
    labels: <GuidedLabel>[_band('day', 'What comes next'), _band('play', 'Games')],
  ),
  GuidedEntry(
    id: 'c.messages', half: GuidedHalf.child, slot: 'child.icons', kind: GuidedKind.childCard,
    sees: 'One big icon she can tap',
    title: 'Messages',
    words: 'Messages from your grown-ups come here. Tap Messages to look.',
    labels: <GuidedLabel>[_band('msgs', 'Look inside')],
  ),
  GuidedEntry(
    id: 'c.stories', half: GuidedHalf.child, slot: 'child.icons', kind: GuidedKind.childCard,
    sees: 'Two big icons',
    title: 'Stories and Show & tell',
    words: 'Stories are to look at and listen to. Show & tell is for sharing a picture.',
    labels: <GuidedLabel>[_band('stories', 'Look and listen'), _band('showtell', 'Share a picture')],
  ),
  GuidedEntry(
    id: 'c.colour', half: GuidedHalf.child, slot: 'child.icons', kind: GuidedKind.childCard,
    sees: 'One big icon and three colours she can tap',
    title: 'Colour',
    words: 'Pick a colour you like today. Tap one.',
    labels: <GuidedLabel>[_band('colour', 'My colour today')],
  ),
  GuidedEntry(
    id: 'c.more', half: GuidedHalf.child, slot: 'child.icons', kind: GuidedKind.childCard,
    sees: 'One big icon',
    title: 'More',
    words: 'More has everything else. It is always there when you want it.',
    labels: <GuidedLabel>[_band('more', 'Everything else')],
  ),
  const GuidedEntry(
    id: 'c.extra', half: GuidedHalf.child, slot: 'child.extra', kind: GuidedKind.childCard,
    sees: 'Only if a newer feature added icons: one card with those icons',
    title: 'And there is more',
    words: 'Here are some new things on your home.',
  ),
  const GuidedEntry(
    id: 'c.done', half: GuidedHalf.child, slot: 'child.close', kind: GuidedKind.childCard,
    sees: 'A big happy picture',
    title: "All done. Let's go!",
    words: 'That is everything. Your home is ready.',
    labels: <GuidedLabel>[GuidedLabel(Icons.home_outlined, 'Home', 'Where we are going')],
    action: "Let's go",
  ),
];
