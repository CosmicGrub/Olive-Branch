// OLIVE BRANCH — care guide REVIEW GATE (guardian shell only). UNVERIFIED — not yet checked by CI's Flutter run.
//
// The app ships no pre-written medical advice before a qualified clinician has reviewed it (MASTERFILE §2.1 and
// §5.23.2). This file is the one place that rule is enforced in code. It is fail-closed: anything that is not an
// explicit, complete REVIEWED record that also passes the wording lint is refused.
//
//  * A release build NEVER returns a guide that is not REVIEWED. [CareGuidePolicy.showsDrafts] is false whenever
//    [releaseMode] is true, whatever the preview switch says.
//  * The preview switch ([CareGuidePolicy.draftPreview]) is off by default. Where it is on (debug builds only) the
//    screens must show [kDraftBannerText] on every draft, permanently.
//  * Only DRAFT_UNREVIEWED can ever be previewed. Any other status (REJECTED, RETIRED, an unknown word) is never shown.
import 'package:flutter/foundation.dart' show kReleaseMode;

import 'care_guide_models.dart';

/// The banner every previewed draft carries. Words only; the screens render it unmissably.
const String kDraftBannerText = 'Draft, not reviewed';

/// Why a guide was refused. For tests and logs only; never shown to a parent or a child.
enum GateRefusal { notReviewed, incompleteReviewRecord, regionNotCovered, wordingLint, unknownStatus }

/// The debug/preview switch for the whole app. OFF by default and only ever read through [CareGuidePolicy.current],
/// which ignores it in a release build. Nothing in lib/ sets it to true (test/care_guide_structure_test.dart checks).
bool careGuidesDraftPreview = false;

class CareGuidePolicy {
  const CareGuidePolicy({this.draftPreview = false, this.releaseMode = kReleaseMode});

  /// The policy the app uses: the global preview switch (off by default), and the build mode.
  factory CareGuidePolicy.current() => CareGuidePolicy(draftPreview: careGuidesDraftPreview);

  /// The debug/preview switch. Off by default.
  final bool draftPreview;

  /// True in a release build. A release build ignores [draftPreview].
  final bool releaseMode;

  bool get showsDrafts => draftPreview && !releaseMode;
}

class GateDecision {
  const GateDecision.allow({this.isDraft = false}) : refusal = null;
  const GateDecision.refuse(GateRefusal r) : refusal = r, isDraft = false;
  final GateRefusal? refusal;
  final bool isDraft;
  bool get allowed => refusal == null;
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A real calendar date in YYYY-MM-DD (not just the right shape: 9999-99-99 and 2030-02-31 are refused).
bool isRealIsoDate(String s) {
  if (!_isoDate.hasMatch(s)) return false;
  final DateTime? d = DateTime.tryParse(s);
  if (d == null) return false;
  final String back = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return back == s;
}

/// A phone number is digits and dialling punctuation only (optionally several separated by a slash): prose, URLs and
/// notes belong elsewhere, and a reviewer must rewrite any number that carries them.
final RegExp _numberShape = RegExp(r'^[+\x28]*[0-9][0-9 ()./-]*(?:/\s*[+\x28]*[0-9][0-9 ()./-]*)*$');
bool isPlainNumber(String s) => _numberShape.hasMatch(s.trim());

/// Words a parent must never meet. The drafts use them to talk to the reviewer, not to a frightened parent.
final List<RegExp> _forbidden = <RegExp>[
  RegExp('clinician', caseSensitive: false),
  RegExp(r'\bsources?\s*\d+', caseSensitive: false),
  // The review-only material (disagreements, unverified items, reviewer questions) is NOT bundled, so a pointer to it
  // would dangle. Any mention of it, or of a list/block/rule elsewhere in the draft, is refused.
  RegExp(r'\bdisagree', caseSensitive: false),
  RegExp(r'\bsee\b[^.;:]{0,60}\b(list|block|section|rule|above|below)\b', caseSensitive: false),
  RegExp(r'\b(in|on) the [\w-]+ (list|block|section)\b', caseSensitive: false),
  RegExp(r'\b(list|block|section) above\b', caseSensitive: false),
  RegExp(r'\breviewers?\b', caseSensitive: false),
  RegExp(r'\bneeds? (a |an )?(\w+ )?review', caseSensitive: false),
  RegExp(r'\bunverified\b', caseSensitive: false),
  RegExp(r'\[\s*\d+(?:\s*[,;-]\s*\d+)*\s*\]'), // a bare citation marker such as [10] or [2, 3]
  RegExp(r'\bDRAFT\b'), // the drafts' own banner wording must not survive into a reviewed guide
  RegExp('not reviewed', caseSensitive: false),
];

// ---------------------------------------------------------------- the dose rule ----
// The app gives no doses: not an amount, not a per-weight amount, not how often. A dose is advice, and advice ships only
// after a clinician has signed off on it, in words the app does not generate. This rule is structural: it recognises the
// SHAPE of a dose (a number or number-word with a medicine unit, a per-kilogram or per-pound amount, a dosing interval)
// and refuses the guide that carries one, whatever the medicine is, so it needs no list of medicines to go stale.
//
// It is deliberately a little too eager. A phrase that merely looks like a dose ("a drop in temperature") fails the guide
// and the reviewer rewords it; the opposite mistake would put a dose in front of a frightened parent. Times and counts
// that are not doses ("24 hours", "10 minutes", "5 back blows", "under 5 kg", "9-8-8") are NOT matched: the unit list is
// medicine units only, and an interval must be a dosing interval ("every 4 hours", "twice daily", "q6h").
const String _doseNumber =
    r'(?:\d+(?:[.,]\d+)?|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|half|quarter|1/2|1/4)';
const String _doseUnit =
    r'(?:mg|mcg|\u00b5g|\u03bcg|ug|g|grams?|milligrams?|micrograms?|ml|mls|millilit(?:re|er)s?|cc|iu|units?|tablets?|tabs?|'
    r'pills?|caplets?|capsules?|puffs?|sprays?|drops?|tsp|teaspoons?|tbsp|tablespoons?|spoonfuls?|dropperfuls?|'
    r'suppositor(?:y|ies)|patch(?:es)?|lozenges?|sachets?|doses?)';

/// The dose shapes. Public so the structure test and the vectors can name them; every one is checked on every
/// parent-facing string by [wordingViolations].
final List<RegExp> doseLintPatterns = <RegExp>[
  // number (or number word) + medicine unit: "5 mg", "10mg", "two tablets", "half a teaspoon" is caught as "a teaspoon"
  RegExp('(?<![\\w.])$_doseNumber\\s*-?\\s*$_doseUnit\\b', caseSensitive: false),
  // per weight: "mg/kg", "5 per kg", "per pound", "/lb"
  RegExp(r'/\s*(?:kg|lbs?)\b|\bper\s+(?:kg|kilo(?:gram)?s?|lbs?|pounds?)\b', caseSensitive: false),
  // dosing interval: "every 4 hours", "every 4 to 6 hours", "q6h", "4-6 hourly"
  RegExp(
      r'\bevery\s+(?:\d+|one|two|three|four|five|six|seven|eight|twelve)(?:\s*(?:to|-|\u2013|or)\s*(?:\d+|four|five|six|eight|twelve))?\s*(?:hours?|hrs?|h)\b',
      caseSensitive: false),
  RegExp(r'\bq\s*\d+\s*h\b', caseSensitive: false),
  RegExp(r'\b\d+\s*(?:-|to)\s*\d+\s*hourly\b', caseSensitive: false),
  // dosing frequency: "twice a day", "three times daily", "once daily", "bid"/"tid"/"qid"
  RegExp(r'\b(?:[a-z]+|\d+)\s+times\s+(?:(?:a|per|each|every)\s+(?:day|24)|daily)', caseSensitive: false),
  RegExp(r'\b(?:once|twice)\s+(?:a\s+day|per\s+day|each\s+day|daily)\b', caseSensitive: false),
  RegExp(r'\b(?:bid|tid|qid|b\.i\.d|t\.i\.d)\b', caseSensitive: false),
  // a ceiling on doses: "maximum 4 doses", "max of 5 doses"
  RegExp(r'\bmax(?:imum)?\s+(?:of\s+)?\d+\s+doses?\b', caseSensitive: false),
];

/// True when [s] has the shape of a dose (see [doseLintPatterns]).
bool hasDosePattern(String s) => doseLintPatterns.any((RegExp r) => r.hasMatch(s));

/// Every string a parent would read, outside the sources list (which is shown as sources, with their own titles).
Iterable<String> parentFacingStrings(CareGuide g) sync* {
  yield g.title;
  if (g.disclaimer != null) yield g.disclaimer!;
  for (final GuideNote n in g.notes) {
    yield n.text;
  }
  if (g.emergencyFirstLine != null) yield g.emergencyFirstLine!.text;
  Iterable<String> item(CareItem i) sync* {
    yield i.text;
    if (i.ages != null) yield i.ages!;
    if (i.group != null) yield i.group!;
    if (i.detail != null) yield i.detail!;
    yield* i.signs;
  }

  for (final CareBlock b in g.blocks) {
    if (b.title != null) yield b.title!;
    for (final CareItem i in b.items) {
      yield* item(i);
    }
  }
  for (final AgeBand a in g.ageBands) {
    yield a.display;
    if (a.text != null) yield a.text!;
    if (a.note != null) yield a.note!;
    for (final CareItem i in a.items) {
      yield* item(i);
    }
  }
  for (final Helpline h in g.helplines) {
    yield h.name;
    yield h.region;
  }
}

/// The helplines a screen may show. Review covers only the regions in the review record, so a helpline for any other
/// region is withheld (phone numbers are the highest-stakes content). A previewed draft shows only its own region.
List<Helpline> helplinesToShow(CareGuide g, {required bool draft}) {
  final Set<String> ok = draft || !g.isReviewed ? <String>{g.region} : g.review.regions.toSet();
  return <Helpline>[for (final Helpline h in g.helplines) if (ok.contains(h.region)) h];
}

/// The parent-facing strings that break the wording rules. Empty = clean.
List<String> wordingViolations(CareGuide g) => <String>[
      for (final String s in parentFacingStrings(g))
        if (_forbidden.any((RegExp r) => r.hasMatch(s)) || hasDosePattern(s)) s,
      for (final Helpline h in g.helplines)
        if (!isPlainNumber(h.number)) h.number,
    ];

/// The one decision. Fail closed.
GateDecision decideGuide(CareGuide g, CareGuidePolicy policy) {
  if (g.status == kStatusReviewed) {
    final GuideReview r = g.review;
    if (r.reviewedOn == null || !isRealIsoDate(r.reviewedOn!) || (r.reviewedBy ?? '').trim().isEmpty || r.regions.isEmpty) {
      return const GateDecision.refuse(GateRefusal.incompleteReviewRecord);
    }
    if (!r.regions.contains(g.region)) return const GateDecision.refuse(GateRefusal.regionNotCovered);
    if (wordingViolations(g).isNotEmpty) return const GateDecision.refuse(GateRefusal.wordingLint);
    return const GateDecision.allow();
  }
  if (g.status == kStatusDraft) {
    return policy.showsDrafts ? const GateDecision.allow(isDraft: true) : const GateDecision.refuse(GateRefusal.notReviewed);
  }
  return const GateDecision.refuse(GateRefusal.unknownStatus);
}
