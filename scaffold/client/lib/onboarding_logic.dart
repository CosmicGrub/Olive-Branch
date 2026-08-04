// OLIVE BRANCH — first-run onboarding logic. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §8.5.
//
// A 1:1 semantic port of packages/onboarding/src/onboarding.ts's name/age/who
// steps, kept close to the TS original (same function names, same shapes,
// same ordering) so the two stay auditable side by side — the same
// discipline lock_controller.dart already applies to lock.ts.
//
// NOT ported here: the §8.5.0 entry-gate (chooseEntry/suggestEntryRole/
// routeFromEntry/ENTRY_CHOICE_GRANTS_NO_AUTHORITY) — that already has a real
// Dart home in entry_gate.dart, owned by a different pass, and this file must
// not touch it. Only the three first-run steps this group's screens actually
// render (name, age, who) are ported.
//
// Every step here is deliberately unable to fail in a way that traps her: the
// worst outcome this product can produce is a child stuck on screen one.

// ================================================================= the name =
class NameStep {
  const NameStep({required this.spelled, required this.fallback, required this.skipped});

  /// Exactly what she typed. Not corrected, not title-cased, not validated.
  final String spelled;
  /// What the guardian entered at setup. Used only if she skips.
  final String fallback;
  final bool skipped;
}

const int maxNameLength = 24;

class AcceptNameOutcome {
  const AcceptNameOutcome.ok(this.step) : ok = true, reason = null;
  const AcceptNameOutcome.tooLong() : ok = false, step = null, reason = 'too_long';

  final bool ok;
  final NameStep? step;
  final String? reason;
}

/// Her spelling stands. If she writes OLIVEE, the app says OLIVEE — see
/// §8.5.1's note on why correcting a child's spelling of her own name here
/// would be a small, precise cruelty.
AcceptNameOutcome acceptName(String typed, String fallback) {
  if (typed.length > maxNameLength) return const AcceptNameOutcome.tooLong();
  final spelled = typed;
  if (spelled.trim().isEmpty) {
    return AcceptNameOutcome.ok(NameStep(spelled: fallback, fallback: fallback, skipped: true));
  }
  return AcceptNameOutcome.ok(NameStep(spelled: spelled, fallback: fallback, skipped: false));
}

/// Mirrors advance()'s inline handling of acceptName's not-ok branch: even a
/// too-long paste produces a usable step (truncated), never a dead end.
NameStep resolveNameStep(String typed, String fallback) {
  final r = acceptName(typed, fallback);
  if (r.ok) return r.step!;
  final truncated = typed.substring(0, maxNameLength);
  return NameStep(spelled: truncated, fallback: fallback, skipped: false);
}

/// She can change it later, any time, without asking. §21.
NameStep renameSelf(NameStep step, String typed) {
  final spelled = (typed.length > maxNameLength ? typed.substring(0, maxNameLength) : typed).trim();
  return spelled.isEmpty ? step : NameStep(spelled: spelled, fallback: step.fallback, skipped: false);
}

// ================================================================== the age =
class AgeStep {
  const AgeStep({required this.selfReported, required this.authoritative,
    required this.disagrees, required this.skipped});

  /// What she tapped. NEVER authoritative.
  final int? selfReported;
  /// Derived from the guardian-entered birth date. This is the real one.
  final int? authoritative;
  /// Recorded rather than silently corrected.
  final bool disagrees;
  final bool skipped;
}

const int minAge = 2, maxAge = 17;

int ageFrom(String birthDate, DateTime now) {
  final b = DateTime.parse(birthDate);
  var a = now.year - b.year;
  final m = now.month - b.month;
  if (m < 0 || (m == 0 && now.day < b.day)) a--;
  return a;
}

/// A child's self-reported age is a UX convenience, not a fact. The
/// guardian's birth date always wins; nothing she taps can raise a gate. See
/// §8.5.2 — this also matters under §10.2, since age is a COPPA-relevant fact
/// and cannot rest on a tap by the subject.
AgeStep acceptAge(int? tapped, String? birthDate, DateTime now) {
  final authoritative = birthDate != null ? ageFrom(birthDate, now) : null;
  if (tapped == null) {
    return AgeStep(selfReported: null, authoritative: authoritative, disagrees: false, skipped: true);
  }
  final clamped = tapped.clamp(minAge, maxAge);
  return AgeStep(selfReported: clamped, authoritative: authoritative,
    disagrees: authoritative != null && authoritative != clamped, skipped: false);
}

/// The age everything else in the product must use.
int? effectiveAge(AgeStep step) => step.authoritative ?? step.selfReported;

// ================================================================== the who =
class Grownup {
  const Grownup({required this.userId, required this.label, required this.joined});

  final String userId;
  /// The guardian's OWN word — Daddy, Papa, Baba, Mum, Mama, Nana.
  final String label;
  /// False until they have accepted the invitation.
  final bool joined;
}

enum WhoKind { noChoice, choose, nobodyYet }

/// Mirrors the TS discriminated union `WhoStep` as one class with kind-gated
/// fields, the same construction LockState already uses in lock_controller.dart
/// for its own multi-shape state.
class WhoStep {
  const WhoStep._({required this.kind, this.only, this.options = const [],
    this.selected = const [], required this.line});

  final WhoKind kind;
  final Grownup? only;
  final List<Grownup> options;
  final List<String> selected;
  final String line;
}

/// §17.1 — single-guardian mode is the default assumption, so when only one
/// adult is in the family graph no choice is presented at all. She is simply
/// told who she is here to talk to. Not a shortcut: asking a child to pick
/// between her parents on the first screen of a co-parenting product would be
/// tactless, and §2.4 keeps the machinery of conflict away from her.
WhoStep whoStep(List<Grownup> grownups) {
  final joined = grownups.where((g) => g.joined).toList();
  if (joined.isEmpty) {
    return const WhoStep._(kind: WhoKind.nobodyYet,
      line: 'Nobody is here yet. We will let you know when they are.');
  }
  if (joined.length == 1) {
    return WhoStep._(kind: WhoKind.noChoice, only: joined.first,
      line: "You're here to talk to ${joined.first.label}.");
  }
  return WhoStep._(kind: WhoKind.choose, options: joined,
    // Everyone selected by default. Deselecting is possible; selecting is
    // not a thing she has to earn.
    selected: joined.map((g) => g.userId).toList(),
    line: 'Who are you here to talk to?');
}

WhoStep toggleWho(WhoStep step, String userId) {
  if (step.kind != WhoKind.choose) return step;
  final has = step.selected.contains(userId);
  final next = has ? step.selected.where((x) => x != userId).toList()
                    : [...step.selected, userId];
  // §2.12 — she may never end up with nobody. The last one cannot be turned off.
  return next.isEmpty ? step
    : WhoStep._(kind: step.kind, options: step.options, selected: next, line: step.line);
}

/// Copy in this flow must not be tested against, praised, or corrected.
const List<String> onboardingForbidden = [
  'correct', 'incorrect', 'wrong', 'try again', 'oops', 'invalid',
  'well done', 'good job', 'nearly', 'almost',
];

class AuditResult {
  const AuditResult(this.ok, this.found);
  final bool ok;
  final List<String> found;
}

AuditResult auditOnboardingCopy(String text) {
  final t = text.toLowerCase();
  final found = onboardingForbidden.where((w) => t.contains(w)).toList();
  return AuditResult(found.isEmpty, found);
}
