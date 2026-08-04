// OLIVE BRANCH — homework photo quality gate + tutor hint guard. UNVERIFIED
// (no Flutter toolchain in tools/verify.sh's automated pipeline). MASTERFILE
// §9.1.
//
// A semantic port of packages/homework/src/capture.ts, keeping the exact
// measured thresholds so a photo that passes/fails here matches the
// TypeScript source of truth. Per that file's own header, these are NOT
// tuned by taste — they are recovery-rate cliffs measured against real
// tesseract 5.3.4 output on generated worksheets:
//
//   skew    0°=100%  2°=100%  4°=83%  6°=67%  8°=33%  10°=0%
//   blur σ  0=100%   1=100%   2=100%  3=50%   4=33%   6=0%
//   size    800px=100%  480px=100%  400px=100%  320px=100%  240px=67%
//
// snapshot_button.dart's camera-capture path reuses this same gate wholesale
// — exactly as capture.ts's own snapshot.ts sibling does — because a
// blurred photo is a blurred photo whether it is headed for OCR or a
// keepsake.
//
// This file is pure Dart, no Flutter import, same posture as
// lock_controller.dart / annotation_canvas.dart.

class ImageStats {
  const ImageStats({
    required this.widthPx,
    required this.heightPx,
    required this.sharpness,
    required this.clipping,
    required this.skewDegrees,
  });

  final int widthPx;
  final int heightPx;

  /// Variance of Laplacian; low means blurred.
  final double sharpness;

  /// 0..1 fraction of pixels at the extremes.
  final double clipping;

  /// Detected page rotation in degrees, -45..45.
  final double skewDegrees;
}

enum QualityFailure { tooSmall, tooBlurred, tooClipped, tooSkewed }

class QualityVerdict {
  const QualityVerdict.ok(this.deskewBy) : ok = true, reason = null, advice = null;
  const QualityVerdict.fail(this.reason, this.advice) : ok = false, deskewBy = null;

  final bool ok;
  final double? deskewBy;
  final QualityFailure? reason;

  /// Written for a child holding a tablet, not for a developer. "Move a bit
  /// closer" is actionable; "resolution below threshold" is not.
  final String? advice;
}

// The first draft of capture.ts set MAX_SKEW_DEG=25 and MIN_EDGE_PX=640 from
// intuition. Both were wrong in opposite directions: 25° passes images that
// recover NOTHING, and 640px rejects images that recover everything. Deskew
// happens before OCR, so the gate only needs to reject what deskew cannot
// save. Values below are copied from the measured constants, not re-derived.
const int minEdgePx = 320; // 240px is the first measured degradation
const double minSharpness = 100; // proxy for σ≈3, where recovery halves
const double maxClipping = 0.35;
const double maxSkewDeg = 6; // 8° already loses two thirds of tokens

QualityVerdict gateImage(ImageStats s) {
  final int shortEdge = s.widthPx < s.heightPx ? s.widthPx : s.heightPx;
  if (shortEdge < minEdgePx) {
    return const QualityVerdict.fail(QualityFailure.tooSmall, 'Move a bit closer to the page.');
  }
  if (s.sharpness < minSharpness) {
    return const QualityVerdict.fail(QualityFailure.tooBlurred, 'Hold still and try again.');
  }
  if (s.clipping > maxClipping) {
    return const QualityVerdict.fail(
        QualityFailure.tooClipped, 'Try moving away from the bright light.');
  }
  if (s.skewDegrees.abs() > maxSkewDeg) {
    return const QualityVerdict.fail(QualityFailure.tooSkewed, 'Line the page up straight.');
  }
  return QualityVerdict.ok(-s.skewDegrees);
}

// ------------------------------------------------------- the tutor guard -----
// §9.1's defensible core is "hint, don't solve" — a safety property with a
// specific failure mode: a model that answers the question destroys the
// authority of a parent who forgot fractions fifteen years ago. Enforced
// here by an OUTPUT guard, not by prompt wording, because a model told not
// to answer will still answer some fraction of the time, and the fraction
// that matters is the one case where a tired parent reads it out loud.

class Problem {
  const Problem({required this.text, required this.forbiddenAnswers});

  /// OCR'd text of one problem.
  final String text;

  /// Values the guard must never see emitted. Derived, not supplied by a
  /// model — see [forbiddenFor].
  final List<String> forbiddenAnswers;
}

enum HintRefusal { containsAnswer, containsEqualsResult, tooDirective, empty }

class HintVerdict {
  const HintVerdict.ok(this.hint) : ok = true, reason = null, safeFallback = null;
  const HintVerdict.fail(this.reason, this.safeFallback) : ok = false, hint = null;

  final bool ok;
  final String? hint;
  final HintRefusal? reason;
  final String? safeFallback;
}

const String _fallbackHint = 'Ask what the bottom numbers have in common.';

/// Phrases that hand over the answer rather than pointing at it — the shapes
/// a helpful model reaches for under pressure.
final List<RegExp> _directivePatterns = <RegExp>[
  RegExp(r'\bthe answer is\b', caseSensitive: false),
  RegExp(r"\bit(?:'s| is)\s+\d", caseSensitive: false),
  RegExp(r'\bequals\s+\d', caseSensitive: false),
  RegExp(r'\bjust write\b', caseSensitive: false),
  RegExp(r'\btype\s+\d', caseSensitive: false),
  RegExp(r'\bso\s+the\s+result\b', caseSensitive: false),
  RegExp(r'\bwhich gives you\b', caseSensitive: false),
];

/// Enforce "hint, don't solve" on the OUTPUT, whatever a model produced.
HintVerdict guardHint(String hint, Problem p) {
  final String h = hint.trim();
  if (h.isEmpty) return const HintVerdict.fail(HintRefusal.empty, _fallbackHint);

  // A bare answer anywhere in the text, as a standalone token.
  for (final String a in p.forbiddenAnswers) {
    final String tok = a.trim();
    if (tok.isEmpty) continue;
    final RegExp re = RegExp('(^|[^\\w/])${RegExp.escape(tok)}([^\\w/]|\$)');
    if (re.hasMatch(h)) return const HintVerdict.fail(HintRefusal.containsAnswer, _fallbackHint);
  }
  // "= 15" or "is 15" following the problem's own operands.
  if (RegExp(r'=\s*-?\d+(\s*/\s*\d+)?').hasMatch(h)) {
    return const HintVerdict.fail(HintRefusal.containsEqualsResult, _fallbackHint);
  }
  for (final RegExp re in _directivePatterns) {
    if (re.hasMatch(h)) return const HintVerdict.fail(HintRefusal.tooDirective, _fallbackHint);
  }
  return HintVerdict.ok(h);
}

/// Derive the values a hint must not contain, from the problem itself.
/// Computed independently of any model, so the guard does not depend on a
/// model self-reporting what the answer was.
List<String> forbiddenFor(String text) {
  final Set<String> out = <String>{};

  // Simple arithmetic: a op b
  final RegExpMatch? m = RegExp(r'(-?\d+)\s*([+\-x*×÷/])\s*(-?\d+)').firstMatch(text);
  if (m != null) {
    final double x = double.parse(m.group(1)!);
    final String op = m.group(2)!;
    final double y = double.parse(m.group(3)!);
    double? r;
    switch (op) {
      case '+': r = x + y; break;
      case '-': r = x - y; break;
      case 'x': case '*': case '×': r = x * y; break;
      case '/': case '÷': r = y != 0 ? x / y : double.nan; break;
    }
    if (r != null && r.isFinite) out.add(_numToken(r));
  }
  // Fractions: a/b op c/d — the common denominator is also a giveaway.
  final RegExpMatch? f =
      RegExp(r'(\d+)\s*/\s*(\d+)\s*([+\-])\s*(\d+)\s*/\s*(\d+)').firstMatch(text);
  if (f != null) {
    final int b = int.parse(f.group(2)!);
    final int d = int.parse(f.group(5)!);
    final int lcm = (b * d) ~/ _gcd(b, d);
    out.add(lcm.toString());
  }
  return out.toList();
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// `15` not `15.0`; `1.5` kept as-is — mirrors the TS version's
/// `Number.isInteger(r * 100)` rounding without a spurious `.0`.
String _numToken(double r) {
  if (r == r.roundToDouble()) return r.toInt().toString();
  final double rounded = (r * 100).roundToDouble() / 100;
  return rounded.toString();
}
