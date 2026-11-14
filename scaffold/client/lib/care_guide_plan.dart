// OLIVE BRANCH — the "For <child>" interface for care guides (guardian shell only).
// UNVERIFIED — not yet checked by CI's Flutter run.
//
// The About-<child> profile does not exist yet. A guide's "For Mia" strip is written against this small interface so
// it starts working the day that profile lands, and until then [NoChildPlan] answers null and the strip renders
// NOTHING (not even the rule line). The strip shows only what a guardian typed into the child's own plan; the app adds
// no medical wording of its own to it.

/// One line of the child's own plan that matters to a guide, e.g. label "Allergy" text "Peanut".
class ChildPlanNote {
  const ChildPlanNote({required this.label, required this.text});
  final String label;
  final String text;
}

/// What the plan has to say for one guide.
class ChildPlanForGuide {
  const ChildPlanForGuide({required this.childName, required this.notes, this.pronoun = 'their'});
  final String childName;

  /// The possessive the guardian chose for this child ("her", "his", "their"). Default "their".
  final String pronoun;
  final List<ChildPlanNote> notes;
}

abstract class ChildPlanSource {
  /// The child's plan notes relevant to [guideId], or null when there is no plan (or nothing relevant).
  Future<ChildPlanForGuide?> forGuide(String guideId);
}

/// Used until the About-child profile exists: there is never a plan.
class NoChildPlan implements ChildPlanSource {
  const NoChildPlan();
  @override
  Future<ChildPlanForGuide?> forGuide(String guideId) async => null;
}

String _possessive(String name) => name.endsWith('s') || name.endsWith('S') ? "$name'" : "$name's";

/// The rule line. It is advice, so it is only shown with a REVIEWED guide (the same flag that gates the guide itself).
String childPlanRuleLine(ChildPlanForGuide p) {
  final String name = _possessive(p.childName);
  return "If $name plan says something different from this guide, follow ${p.pronoun} plan and call ${p.pronoun} doctor.";
}
