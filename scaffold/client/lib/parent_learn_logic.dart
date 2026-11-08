// OLIVE BRANCH — Parent Learn, pure logic (guardian-only education content).
// No longer UNVERIFIED — verified by CI against the TypeScript module's golden vectors.
// A 1:1 semantic port of packages/parent-learn/src/learn.ts, kept close to the TS
// original (same names, same shapes, same ordering) so the two stay auditable side
// by side. Research: docs/superpowers/specs/2026-11-07-parenting-styles-education-research.md.
//
// Nothing here touches a socket, a clock, storage or a widget.
// client/test/parent_learn_logic_test.dart runs this file against
// packages/parent-learn/test/vectors.json, which the TypeScript module generates.
//
//  L1  Guardian-only. A child, a sitter or any non-guardian never reads Learn.
//  L2  A reflection belongs to the guardian who made it. No export, no share.
//  L3  Every card has an evidence label and an https source, never claims a
//      style CAUSES an outcome, and never labels a person.
//  L4  The message check is off unless opted in; hints only; stores nothing.
//  L5  The two-home rules list shares only the four core categories.

enum Evidence { strong, moderate, weak, contested }

class LearnSource {
  const LearnSource(this.label, this.url);
  final String label;
  final String url;
}

class LearnCard {
  const LearnCard({
    required this.id,
    required this.topic,
    required this.title,
    required this.body,
    required this.evidence,
    required this.sources,
    this.ages,
  });
  final String id;
  final String topic;
  final String title;
  final String body;
  final Evidence evidence;
  final List<LearnSource> sources;
  final List<int>? ages;

  LearnCard withBody(String b) => LearnCard(
      id: id, topic: topic, title: title, body: b, evidence: evidence, sources: sources, ages: ages);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'topic': topic,
        'title': title,
        'body': body,
        'evidence': evidence.name,
        'sources': <Object?>[
          for (final s in sources) <String, Object?>{'label': s.label, 'url': s.url}
        ],
        if (ages != null) 'ages': ages,
      };
}

const LearnSource _aap = LearnSource('AAP: Disciplining Your Child',
    'https://www.healthychildren.org/English/family-life/family-dynamics/communication-discipline/Pages/Disciplining-Your-Child.aspx');
const LearnSource _chao = LearnSource('Chao 1994',
    'https://aacdrpubs.faculty.ucdavis.edu/wp-content/uploads/sites/211/2015/03/chao001.pdf');
const LearnSource _ds93 = LearnSource(
    'Darling and Steinberg 1993', 'https://data.zhenzhi.com/details/1/1001468350');
const LearnSource _ak14 = LearnSource('Avinun and Knafo 2014',
    'https://cris.huji.ac.il/en/publications/parenting-as-a-reaction-evoked-by-childrens-genotype-a-meta-analy/');
const LearnSource _nd = LearnSource(
    'Notre Dame: couples and kids', 'https://shaw.nd.edu/research/couples-and-kids');
const LearnSource _pd = LearnSource('ParentData: is gentle parenting evidence-based',
    'https://parentdata.org/ask/is-gentle-parenting-evidence-based-does-it-actually-work');
const LearnSource _tripleP = LearnSource('Emotion-enhanced Triple P thesis',
    'https://openaccess.wgtn.ac.nz/articles/thesis/Integrating_emotion_into_behaviourally-based_parenting_programmes_can_this_enhance_outcomes_for_child_conduct_problems_/17006110');
const LearnSource _bielefeld = LearnSource(
    'Bielefeld longitudinal study', 'https://pub.uni-bielefeld.de/record/1591258');
const LearnSource _fatherhood = LearnSource('Fatherhood Institute briefing',
    'https://fatherhoodinstitute.org/_files/ugd/efff1d_dc63e949baaa4de2ac96d5b562234262.pdf');

const List<LearnCard> learnCards = <LearnCard>[
  LearnCard(
      id: 'two-dimensions',
      topic: 'style',
      title: 'Two things, not four boxes',
      body:
          'Home feels like a mix of warmth and expectations. The four named styles are corners of that map, not types of person. Most days you move around it.',
      evidence: Evidence.strong,
      sources: <LearnSource>[_ds93]),
  LearnCard(
      id: 'warm-and-clear',
      topic: 'style',
      title: 'Warm and clear',
      body:
          'Children tend to do well on school, mood and friendships when warmth and clear limits go together. This is a link in studies, not a promise, and it is not risk-free.',
      evidence: Evidence.moderate,
      sources: <LearnSource>[_ds93, _pd]),
  LearnCard(
      id: 'climate-and-tools',
      topic: 'style',
      title: 'Climate and tools',
      body:
          'Style is the emotional climate. Practices are the tools. The same tool, such as a time-out, lands differently in a warm home than in a cold one.',
      evidence: Evidence.moderate,
      sources: <LearnSource>[_ds93]),
  LearnCard(
      id: 'child-shapes-parent',
      topic: 'style',
      title: 'Children shape parents too',
      body:
          'Twin studies estimate that about a quarter of the variation in parenting is driven by the child. Parent and child influence each other, so nobody is to blame for the whole picture.',
      evidence: Evidence.strong,
      sources: <LearnSource>[_ak14]),
  LearnCard(
      id: 'culture-changes-meaning',
      topic: 'style',
      title: 'Culture changes the meaning',
      body:
          'A firm, high-expectation style can mean care and training in some families and coldness in others. Research found the same style linked to opposite school results in different communities.',
      evidence: Evidence.contested,
      sources: <LearnSource>[_chao]),
  LearnCard(
      id: 'gentle-with-limits',
      topic: 'style',
      title: 'Gentle means kind and firm',
      body:
          'Gentle parenting has no studies of its own. Its ingredients, warmth, validation and limits that are held, match research on authoritative parenting. The risk is dropping the limits. Check: did I say the limit, and did I hold it?',
      evidence: Evidence.weak,
      sources: <LearnSource>[_pd]),
  LearnCard(
      id: 'short-time-out',
      topic: 'discipline',
      title: 'A short, calm time-out',
      body:
          'Name what happened, use a boring safe spot, stay calm and quiet, then reconnect. About one minute per year of age. Skip long isolation and punishing tears.',
      evidence: Evidence.strong,
      sources: <LearnSource>[_aap],
      ages: <int>[2, 8]),
  LearnCard(
      id: 'avoid-hitting',
      topic: 'discipline',
      title: 'Hitting does not teach',
      body:
          'Pediatric guidance advises against physical punishment. It is less effective than time-outs or losing a privilege and is linked to more defiance.',
      evidence: Evidence.strong,
      sources: <LearnSource>[_aap]),
  LearnCard(
      id: 'specific-praise',
      topic: 'discipline',
      title: 'Specific praise',
      body: 'Name the thing they did. "You shared the red block" lands better than "good boy".',
      evidence: Evidence.moderate,
      sources: <LearnSource>[_aap],
      ages: <int>[3, 8]),
  LearnCard(
      id: 'plain-instructions',
      topic: 'communication',
      title: 'Say it plainly',
      body:
          'If it is an instruction, say it as one, once, in specific words. "Shoes on, please" works better than "Can you put your shoes on?"',
      evidence: Evidence.moderate,
      sources: <LearnSource>[_aap]),
  LearnCard(
      id: 'emotion-coaching',
      topic: 'communication',
      title: 'Naming feelings',
      body:
          "Emotion coaching reliably changes what parents do. Evidence that it improves 5 to 7 year olds' emotion skills is still thin and mostly parent-reported.",
      evidence: Evidence.weak,
      sources: <LearnSource>[_tripleP],
      ages: <int>[4, 8]),
  LearnCard(
      id: 'how-parents-fight',
      topic: 'conflict',
      title: 'How you disagree matters most',
      body:
          'Hostility and withdrawal between parents are linked to more child problems because a child may feel the family is unsafe. Calm disagreement that gets resolved is not harmful.',
      evidence: Evidence.strong,
      sources: <LearnSource>[_nd]),
  LearnCard(
      id: 'out-of-the-middle',
      topic: 'coparenting',
      title: 'Keep your child out of the middle',
      body:
          'No messengers, no questions about the other home, no criticism of the other parent in earshot.',
      evidence: Evidence.strong,
      sources: <LearnSource>[_nd]),
  LearnCard(
      id: 'rules-that-match',
      topic: 'coparenting',
      title: 'What is worth matching',
      body:
          'Core routines such as bedtime, screens, homework and safety are the better-supported place to line up. Evidence that matching whole styles matters is mixed, and low conflict matters more.',
      evidence: Evidence.moderate,
      sources: <LearnSource>[_bielefeld, _fatherhood]),
  LearnCard(
      id: 'repair',
      topic: 'repair',
      title: 'After you lost your temper',
      body:
          'Calm yourself first, go back and name it, say it was yours, then reconnect. Mistakes happen. A mistake does not make anyone bad.',
      evidence: Evidence.strong,
      sources: <LearnSource>[_aap]),
  LearnCard(
      id: 'siblings',
      topic: 'discipline',
      title: 'When siblings fight',
      body:
          'Step in only if someone could be hurt. Name each feeling, ask what they could try, then notice the fix. Common practice, but no sibling-specific trials were found.',
      evidence: Evidence.weak,
      sources: <LearnSource>[_aap],
      ages: <int>[4, 8]),
];

// ---------------------------------------------------------------- principals
class LearnPrincipal {
  const LearnPrincipal(this.kind, this.id);
  final String kind; // 'guardian' | 'child' | 'adult'
  final String id;
}

/// L1
bool canReadLearn(LearnPrincipal? p) => p != null && p.kind == 'guardian';

/// L2: only the guardian who made a reflection may read it.
bool canReadReflection(LearnPrincipal? p, String ownerId) =>
    canReadLearn(p) && ownerId.isNotEmpty && p!.id == ownerId;

// ------------------------------------------------------------------ settings
const List<String> _reflectionModes = <String>['off', 'session', 'saved'];
const List<String> _framings = <String>['neutral', 'culture-note', 'values-first'];

class LearnSettings {
  const LearnSettings({
    this.reflection = 'session',
    this.framing = 'neutral',
    this.rulesList = false,
    this.messageCheck = false,
  });
  final String reflection;
  final String framing;
  final bool rulesList;
  final bool messageCheck;

  LearnSettings copyWith({String? reflection, String? framing, bool? rulesList, bool? messageCheck}) =>
      LearnSettings(
        reflection: reflection ?? this.reflection,
        framing: framing ?? this.framing,
        rulesList: rulesList ?? this.rulesList,
        messageCheck: messageCheck ?? this.messageCheck,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'reflection': reflection,
        'framing': framing,
        'rulesList': rulesList,
        'messageCheck': messageCheck,
      };

  @override
  bool operator ==(Object other) =>
      other is LearnSettings &&
      other.reflection == reflection &&
      other.framing == framing &&
      other.rulesList == rulesList &&
      other.messageCheck == messageCheck;

  @override
  int get hashCode => Object.hash(reflection, framing, rulesList, messageCheck);
}

/// Most private choice for every optional feature.
const LearnSettings defaultLearnSettings = LearnSettings();

/// Untrusted input: unknown or wrongly-typed fields fall back to the default.
LearnSettings parseLearnSettings(Object? raw) {
  final Map<Object?, Object?> o = raw is Map ? raw.cast<Object?, Object?>() : const <Object?, Object?>{};
  final Object? r = o['reflection'];
  final Object? f = o['framing'];
  return LearnSettings(
    reflection: (r is String && _reflectionModes.contains(r)) ? r : defaultLearnSettings.reflection,
    framing: (f is String && _framings.contains(f)) ? f : defaultLearnSettings.framing,
    rulesList: o['rulesList'] == true,
    messageCheck: o['messageCheck'] == true,
  );
}

/// Whether a reflection may be written to storage at all.
bool mayStoreReflection(LearnSettings s) => s.reflection == 'saved';

// ---------------------------------------------------------------- reflection
class DayMirror {
  const DayMirror(this.headline, this.prompt);
  final String headline;
  final String prompt;
}

double _clamp100(num n) => n.isFinite ? n.clamp(0, 100).toDouble() : 50.0;

/// Describes the day, never the person. No label, no score.
DayMirror describeDay(num warmth, num expectations) {
  final bool hw = _clamp100(warmth) >= 50;
  final bool he = _clamp100(expectations) >= 50;
  if (hw && he) {
    return const DayMirror('Warm, with clear limits.', 'Notice: what made that possible today?');
  }
  if (!hw && he) {
    return const DayMirror('Firm today, with less warmth.',
        'Notice: what was going on for you? One small warm moment can change the day.');
  }
  if (hw && !he) {
    return const DayMirror('Warm today, with looser limits.',
        'Notice: was it a choice, or were you tired? One clear limit may be enough.');
  }
  return const DayMirror('Low on both today.',
      'Notice: are you okay? Support is fine to ask for. Tomorrow is a fresh day.');
}

// -------------------------------------------------------------- card queries
const String _cultureNote = ' What this means can differ by family and culture.';

List<LearnCard> learnCardsFor(LearnPrincipal? p, LearnSettings s, {int? age}) {
  if (!canReadLearn(p)) return const <LearnCard>[];
  return <LearnCard>[
    for (final LearnCard c in learnCards)
      if (age == null || c.ages == null || (age >= c.ages![0] && age <= c.ages![1]))
        (s.framing == 'culture-note' && c.topic == 'style' && c.id != 'culture-changes-meaning')
            ? c.withBody(c.body + _cultureNote)
            : c,
  ];
}

final RegExp _causal = RegExp(r"\b(causes?|caused|produces?|makes? your child|will make|guarantees?)\b",
    caseSensitive: false);
final RegExp _labelPerson = RegExp(
    r"\byou are (a|an) (permissive|authoritarian|authoritative|neglectful|bad|lazy|helicopter)\b",
    caseSensitive: false);
final RegExp _noRisk = RegExp(r"\brisks?:\s*none\b|\bno risks?\b", caseSensitive: false);

/// L3: a list of violations; empty means the content passes.
List<String> lintLearnCards(List<LearnCard> cards) {
  final List<String> out = <String>[];
  final Set<String> ids = <String>{};
  for (final LearnCard c in cards) {
    if (ids.contains(c.id)) out.add('${c.id}: duplicate id');
    ids.add(c.id);
    if (c.sources.isEmpty) out.add('${c.id}: no source');
    for (final LearnSource s in c.sources) {
      if (!s.url.startsWith('https://')) out.add('${c.id}: non-https source');
    }
    if (_causal.hasMatch(c.body) || _causal.hasMatch(c.title)) out.add('${c.id}: causal claim');
    if (_labelPerson.hasMatch(c.body) || _labelPerson.hasMatch(c.title)) {
      out.add('${c.id}: labels a person');
    }
    if (_noRisk.hasMatch(c.body)) out.add('${c.id}: claims no risk');
  }
  return out;
}

// ------------------------------------------------------------- message check
class MessageHint {
  const MessageHint(this.flag, this.hint);
  final String flag;
  final String hint;
}

class _Rule {
  const _Rule(this.flag, this.re, this.hint);
  final String flag;
  final RegExp re;
  final String hint;
}

final List<_Rule> _rules = <_Rule>[
  _Rule('absolute', RegExp(r"\byou (always|never)\b", caseSensitive: false),
      'Try the one thing that happened: "On Friday bedtime was late."'),
  _Rule('blame', RegExp(r"\b(your fault|because of you|you('| a)re (the reason|to blame))\b", caseSensitive: false),
      'Describe the effect, not who is at fault.'),
  _Rule('contempt', RegExp(r"\b(idiot|stupid|pathetic|useless|incompetent|worthless)\b", caseSensitive: false),
      'Leave out the insult. It makes the real point harder to hear.'),
  _Rule(
      'child-messenger',
      RegExp(r"\b(tell|ask) (your|the) (dad|mom|mum|mother|father|parent)\b|\bhave (her|him|them) tell\b",
          caseSensitive: false),
      'Send this to the other guardian directly. Please keep the child out of it.'),
  _Rule(
      'questioning-child',
      RegExp(r"\bask (her|him|them|\w+) what (dad|mom|mum|mother|father|he|she)\b", caseSensitive: false),
      'Please do not question the child about the other home.'),
  _Rule('threat', RegExp(r"\b(i('| wi)ll (take|see you in)|you('| wi)ll regret|or else)\b", caseSensitive: false),
      'Say what you need and by when, without a threat.'),
];

const int maxCheckChars = 4000;

/// L4. Null unless the guardian opted in. Never stores or sends. Hints only.
List<MessageHint>? checkMessage(LearnPrincipal? p, LearnSettings s, Object? text) {
  if (!canReadLearn(p) || !s.messageCheck) return null;
  if (text is! String) return const <MessageHint>[];
  final String t = text.length > maxCheckChars ? text.substring(0, maxCheckChars) : text;
  final List<MessageHint> out = <MessageHint>[];
  for (final _Rule r in _rules) {
    if (r.re.hasMatch(t) && !out.any((MessageHint h) => h.flag == r.flag)) {
      out.add(MessageHint(r.flag, r.hint));
    }
  }
  return out;
}

// --------------------------------------------------------- two-home rules list
const List<String> ruleCategories = <String>['bedtime', 'screens', 'homework', 'safety'];

class RuleItem {
  const RuleItem(this.category, this.text);
  final String category;
  final String text;
}

/// L5. Empty unless opted in; known categories only, bounded text, nothing else.
List<RuleItem> shareableRules(LearnPrincipal? p, LearnSettings s, Object? items) {
  if (!canReadLearn(p) || !s.rulesList || items is! List) return const <RuleItem>[];
  final List<RuleItem> out = <RuleItem>[];
  for (final Object? it in items.take(20)) {
    if (it is! Map) continue;
    final Object? category = it['category'];
    final Object? text = it['text'];
    if (category is! String || !ruleCategories.contains(category)) continue;
    if (text is! String || text.trim().isEmpty) continue;
    final String t = text.trim();
    out.add(RuleItem(category, t.length > 200 ? t.substring(0, 200) : t));
  }
  return out;
}
