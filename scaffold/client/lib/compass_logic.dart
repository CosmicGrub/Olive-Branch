// OLIVE BRANCH — suite I COMPASS, pure logic: a gentle two-step questionnaire for
// a guardian, a plain rules table that suggests which suites to look at, the two
// local accessibility profiles, and the alert cue. No longer UNVERIFIED —
// verified by CI (client/test/compass_logic_test.dart).
//
// GUARDIAN SIDE ONLY, ON THIS DEVICE ONLY. The answers are a guardian's own
// words about the family's days ("who is in her life", "what would help her").
// They stay in a sealed local area; nothing is sent, and nothing the child sees
// is built from them except the suites a guardian then CHOOSES to switch on.
//
// WHAT THIS IS NOT. It does not score the child or the family, label the child,
// diagnose or claim to be smart. [compassRules] is a plain table: "if any of
// these answers was chosen, mention this suite or profile, and say why in a
// sentence". It is read top to bottom, there is no weight, no number and no
// learning; the same answers always give the same list, in the same order, and
// the list is capped at [maxSuggestions] (the rest are on the suites shelf). A
// suggestion changes nothing by itself: a guardian taps to switch a suite on.
// "Not now" remembers nothing, and an empty answer ("not sure", "skip") is a
// complete answer.
//
// THE TWO PROFILES change PRESENTATION DEFAULTS on this device and nothing else:
// they write the existing accessibility settings (read aloud, reduce motion,
// roomier reading, captions wish) and shape the alert cue; they never touch what
// is shown, who can see what, or any family data. Flashing is never on for
// anyone, so a visual alert is a steady border, a picture and words.
library;

import 'access_settings.dart';

const int maxSuggestions = 5;

// ============================================================== questions ====
/// One tickable answer. [label] is what the guardian reads; it describes the
/// family's days or a support, never the child.
class CompassOption {
  const CompassOption(this.id, this.label);
  final String id;
  final String label;
}

/// Step 1: who is in her life.
const List<CompassOption> compassWhoOptions = <CompassOption>[
  CompassOption('twoHomes', 'She sleeps in more than one home'),
  CompassOption('deviceTravels', 'This device goes with her to another home'),
  CompassOption('parentAway', 'A parent who is away for a while (work, service, distance)'),
  CompassOption('stepAdult', 'A step-parent or a parent\'s partner is part of her days'),
  CompassOption('grandparent', 'A grandparent or another relative helps look after her'),
  CompassOption('siblings', 'Brothers or sisters, perhaps in another home'),
  CompassOption('carer', 'A carer who is not a parent (foster or kinship care)'),
  CompassOption('loss', 'We have lost someone close'),
];

/// Step 2: what would help. Supports, not conditions.
const List<CompassOption> compassNeedsOptions = <CompassOption>[
  CompassOption('knowNext', 'Knowing what comes next'),
  CompassOption('quiet', 'A calm app: less sound and motion'),
  CompassOption('pictures', 'Pictures, not just words'),
  CompassOption('showFeelings', 'A gentle way to show how today feels'),
  CompassOption('seeAlerts', 'Alerts she can see, not only hear'),
  CompassOption('signing', 'Sign language at home'),
  CompassOption('medical', 'Regular medicine or hospital visits'),
  CompassOption('sitter', 'Another adult sometimes minds her for an evening'),
  CompassOption('school', 'Someone at school needs to know what helps'),
  CompassOption('keepsakes', 'Keeping letters and firsts safe for later'),
];

final Set<String> _whoIds = <String>{for (final CompassOption o in compassWhoOptions) o.id};
final Set<String> _needIds = <String>{for (final CompassOption o in compassNeedsOptions) o.id};

String? optionLabel(String id) {
  for (final CompassOption o in <CompassOption>[...compassWhoOptions, ...compassNeedsOptions]) {
    if (o.id == id) return o.label;
  }
  return null;
}

/// A guardian's answers. Any number may be chosen, none is fine. Unknown ids are
/// dropped on the way in, never kept.
class CompassAnswers {
  const CompassAnswers({this.who = const <String>{}, this.needs = const <String>{}});
  final Set<String> who;
  final Set<String> needs;

  bool get isEmpty => who.isEmpty && needs.isEmpty;
  Set<String> get all => <String>{...who, ...needs};

  CompassAnswers withWho(String id, bool on) => !_whoIds.contains(id)
      ? this
      : CompassAnswers(who: on ? <String>{...who, id} : (<String>{...who}..remove(id)), needs: needs);

  CompassAnswers withNeed(String id, bool on) => !_needIds.contains(id)
      ? this
      : CompassAnswers(who: who, needs: on ? <String>{...needs, id} : (<String>{...needs}..remove(id)));

  /// Stored in the table's own order so the document is the same however the
  /// answers were ticked.
  Map<String, Object?> toJson() => <String, Object?>{
        'who': <String>[for (final CompassOption o in compassWhoOptions) if (who.contains(o.id)) o.id],
        'needs': <String>[for (final CompassOption o in compassNeedsOptions) if (needs.contains(o.id)) o.id],
      };

  static CompassAnswers fromJson(Object? j) {
    if (j is! Map) return const CompassAnswers();
    Set<String> pick(Object? raw, Set<String> known) =>
        raw is List ? <String>{for (final Object? x in raw) if (x is String && known.contains(x)) x} : <String>{};
    return CompassAnswers(who: pick(j['who'], _whoIds), needs: pick(j['needs'], _needIds));
  }

  @override
  bool operator ==(Object other) =>
      other is CompassAnswers && other.who.length == who.length && other.needs.length == needs.length &&
      other.who.containsAll(who) && other.needs.containsAll(needs);

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(who), Object.hashAllUnordered(needs));
}

// ================================================================= rules =====
enum SuggestionKind { suite, profile }

/// The suites a guardian can switch on or off, and the two profiles.
const List<String> suiteKeysOnShelf = <String>['rhythm', 'voice', 'village', 'growing', 'care'];
const String profileAway = 'awayFromHome';
const String profileDeaf = 'deafHoh';
const List<String> profileKeys = <String>[profileAway, profileDeaf];

/// One row of the table: any one of [anyOf] chosen mentions [key], for [reason].
class CompassRule {
  const CompassRule(this.anyOf, this.kind, this.key, this.reason);
  final List<String> anyOf;
  final SuggestionKind kind;
  final String key;
  final String reason;
}

/// THE TABLE. Read top to bottom. No weights, no numbers.
const List<CompassRule> compassRules = <CompassRule>[
  CompassRule(<String>['twoHomes', 'deviceTravels', 'knowNext'], SuggestionKind.suite, 'rhythm',
      'A routine, a first-then card and a bag list in pictures show what comes next. Kept on this device.'),
  CompassRule(<String>['quiet'], SuggestionKind.suite, 'rhythm',
      '"How the app feels" turns sound, motion and brightness down on her device.'),
  CompassRule(<String>['pictures', 'showFeelings'], SuggestionKind.suite, 'voice',
      'A picture board to say things with, a weather picture only she sees, and a worry box only she opens.'),
  CompassRule(<String>['stepAdult', 'carer'], SuggestionKind.suite, 'village',
      'Her people in pictures, and a picture story you write yourself and release only when you choose.'),
  CompassRule(<String>['grandparent'], SuggestionKind.suite, 'village',
      'A large-print page for a grandparent: up to four cards you write and a phone line shown as text.'),
  CompassRule(<String>['siblings'], SuggestionKind.suite, 'village',
      'A shelf where brothers and sisters who share this device leave each other pictures.'),
  CompassRule(<String>['sitter', 'school'], SuggestionKind.suite, 'village',
      'A one-page sitter pass and a school summary you write, kept here, to show on the screen.'),
  CompassRule(<String>['parentAway', 'keepsakes', 'loss'], SuggestionKind.suite, 'growing',
      'A time capsule for a letter to open on a day you choose, a memory box, and first times.'),
  CompassRule(<String>['medical'], SuggestionKind.suite, 'care',
      'A care binder, hospital mode and appointment lists, for grown-ups only; she never sees them.'),
  CompassRule(<String>['deviceTravels'], SuggestionKind.profile, profileAway,
      'Calmer defaults for a device used in another home: words can be heard and motion is reduced.'),
  CompassRule(<String>['seeAlerts', 'signing'], SuggestionKind.profile, profileDeaf,
      'Alerts she can see, bigger reading room and no cue that only makes a sound.'),
];

/// One thing mentioned for the guardian to look at. [reasons] are the table's
/// own sentences, in table order; [because] are the answers that matched.
class Suggestion {
  const Suggestion({required this.kind, required this.key, required this.reasons, required this.because});
  final SuggestionKind kind;
  final String key;
  final List<String> reasons;
  final List<String> because;
}

/// The suggestions for [a]: pure, deterministic, capped. The order is the
/// table's, never a ranking of the family.
List<Suggestion> suggest(CompassAnswers a, {int max = maxSuggestions}) {
  final Map<String, List<String>> reasons = <String, List<String>>{};
  final Map<String, Set<String>> because = <String, Set<String>>{};
  final List<(SuggestionKind, String)> order = <(SuggestionKind, String)>[];
  final Set<String> chosen = a.all;
  for (final CompassRule r in compassRules) {
    final List<String> hit = <String>[for (final String id in r.anyOf) if (chosen.contains(id)) id];
    if (hit.isEmpty) continue;
    final String k = '${r.kind.name}:${r.key}';
    if (!reasons.containsKey(k)) order.add((r.kind, r.key));
    reasons.putIfAbsent(k, () => <String>[]).add(r.reason);
    because.putIfAbsent(k, () => <String>{}).addAll(hit);
  }
  return <Suggestion>[
    for (final (SuggestionKind, String) e in order.take(max < 0 ? 0 : max))
      Suggestion(
          kind: e.$1, key: e.$2, reasons: reasons['${e.$1.name}:${e.$2}']!,
          because: <String>[for (final CompassOption o in <CompassOption>[...compassWhoOptions, ...compassNeedsOptions])
            if (because['${e.$1.name}:${e.$2}']!.contains(o.id)) o.id]),
  ];
}

// ============================================================ the builder ====
/// Facts the family builder already holds, offered as a quiet hint beside the
/// questions (never ticked for her). Takes plain counts so this file imports no
/// family type.
List<String> builderHints({required int sleepingHomes, required bool someoneAway}) => <String>[
      if (sleepingHomes > 1) 'twoHomes',
      if (someoneAway) 'parentAway',
    ];

// ============================================================== profiles =====
/// What a profile changes on this device. Everything is a presentation default.
class ProfileDefaults {
  const ProfileDefaults({
    required this.id, required this.title, required this.summary, required this.changes,
    this.readAloud, this.reduceMotion, this.roomierReading, this.captions, this.visualAlerts,
  });
  final String id;
  final String title;

  /// What this is for, in one plain sentence (about the device, not the child).
  final String summary;

  /// What it changes, as short plain lines the screen lists.
  final List<String> changes;
  final bool? readAloud, reduceMotion, roomierReading, captions, visualAlerts;
}

const ProfileDefaults awayProfile = ProfileDefaults(
  id: profileAway,
  title: 'Device used in another home',
  summary: 'For a device she uses away from where she usually lives. Only presentation changes.',
  changes: <String>['Words can be heard (read aloud on)', 'Motion reduced'],
  readAloud: true, reduceMotion: true,
);

const ProfileDefaults deafProfile = ProfileDefaults(
  id: profileDeaf,
  title: 'Alerts she can see',
  summary: 'For a child who is deaf or hard of hearing. Pictures and words lead; no cue is sound only.',
  changes: <String>[
    'Read aloud off (pictures and words lead)', 'Roomier reading, ready for captions',
    'A captions wish is recorded (live captions are not built yet)',
    'Alerts show a picture and words that stay until tapped, with a gentle buzz',
  ],
  readAloud: false, roomierReading: true, captions: true, visualAlerts: true,
);

const List<ProfileDefaults> allProfiles = <ProfileDefaults>[awayProfile, deafProfile];

ProfileDefaults? profileById(Object? id) {
  for (final ProfileDefaults p in allProfiles) {
    if (p.id == id) return p;
  }
  return null;
}

/// [current] with a profile's defaults laid over it. Only the settings the
/// profile names change; every other setting is left exactly as the guardian had it.
AccessSettings applyProfileTo(AccessSettings current, ProfileDefaults p) => current.copyWith(
      readAloud: p.readAloud, reduceMotion: p.reduceMotion, roomierReading: p.roomierReading,
      captions: p.captions, visualAlerts: p.visualAlerts);

// ============================================================ alert cues =====
enum AlertKind { pictureLeft, storyReady, general }

/// How one alert reaches her. [visual] and [text] are ALWAYS present and no cue
/// here makes a sound, so none is ever sound only. Nothing flashes.
class AlertCue {
  const AlertCue({required this.text, required this.haptic, required this.persistent});
  final String text;
  final bool visual = true;
  final bool haptic;

  /// Stays until she taps it, instead of fading after a moment.
  final bool persistent;
  bool get flashes => false;
}

String alertText(AlertKind k) => switch (k) {
      AlertKind.pictureLeft => 'A picture is on the shelf',
      AlertKind.storyReady => 'A story is ready for you',
      AlertKind.general => 'Something new is here',
    };

/// The cue for [kind] under the child's accessibility settings (the ones a
/// guardian, or a Compass profile, set). Her screens can read exactly this and
/// nothing about why.
AlertCue cueFor(AccessSettings s, AlertKind kind) =>
    AlertCue(text: alertText(kind), haptic: s.visualAlerts, persistent: s.visualAlerts);
