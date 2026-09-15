// OLIVE BRANCH — shared spacing/radius design tokens. No longer UNVERIFIED —
// verified by CI (a Flutter toolchain runs for real in tools/verify.sh's
// automated pipeline).
//
// docs/superpowers/specs/2026-09-15-design-tokens-named-migration-design.md
// (UI/UX review theme #4). NOT an extension of theme.dart — that file's whole
// shape (AppTheme/ThemePalette/ThemeBrightness/ThemeController) is built
// around the palette-and-brightness contract; a spacing scale has nothing to
// do with it, and widening that file's contract for an unrelated concern is
// exactly the kind of undeclared scope-widening this codebase's own
// precedent (child_theme_preference.dart's migration header, among others)
// argues against. form_factors.dart is also confirmed the wrong home — its
// own doc comment on comfortableReadingWidth explicitly guards against being
// treated as a general token source.
//
// Values match what's ALREADY the de facto majority across this codebase
// (confirmed by direct grep, not invented): 16/12/24/20 dominate existing
// EdgeInsets.all() calls, 12/16 dominate existing BorderRadius.circular()
// calls. This codifies the existing standard, not a new arbitrary scale —
// minimizing visual change at every site this spec actually touches.
//
// Deliberately narrow scope: this spec applies these tokens only to the
// concretely-named problem spots the review found (see the spec doc's own
// Fix #1-#4) — not a retrofit of the whole app. New code uses these tokens
// going forward; existing drift outside those spots is not chased down.

class AppSpacing {
  const AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  const AppRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}
