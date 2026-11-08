// No longer UNVERIFIED — verified by CI (client/test/ui/olive_ui_test.dart).
// OLIVE BRANCH — the component library's single seam to the design tokens.
//
// The premium kit (docs/superpowers/mockups/live/kit.js + overhaul.css) is the REFERENCE the Flutter
// app must match. Its CSS variables (--pri, --priC, --surface2, --ink3, --shadow2 ...) are mapped here,
// once, onto what the app already has: the Material [ColorScheme] built by theme_data.dart, the
// [OliveSemantic] extension (ok/warn/info and the day-part bands), and [AppRadius]/[AppSpacing] from
// design_tokens.dart. No component in lib/ui reads a colour any other way and none hard-codes a hex
// value, so when the generated design tokens (feat/design-parity-tokens) land, THIS FILE is the only
// one that changes.
//
// Names follow the kit so a prototype CSS rule and its Flutter counterpart read the same:
//   bg surface surface2 surface3 line edge ink ink2 ink3 pri priD priC priC2 onPri onPriC accent accentC
//   ok okC warn warnC bad badC info infoC  dpMorning dpDay dpAfternoon dpEvening dpBed dpNight
import 'package:flutter/material.dart';

import '../access_scope.dart' show motionDuration;
import '../design_tokens.dart';
import '../design_tokens_generated.dart' show DesignRole;
import '../theme_data.dart';

/// Palette tokens the generated art (olive_art_data.dart) refers to by name. The generator
/// (tools/gen-olive-icons.mjs) refuses any name that is not listed here.
enum OTok {
  bg, surface, surface2, surface3, line, edge, ink, ink2, ink3, pri, priD, priC, priC2,
  onPri, onPriC, accent, accentC, ok, okC, warn, warnC, bad, badC, info, infoC,
  dpMorning, dpDay, dpAfternoon, dpEvening, dpBed, dpNight,
}

/// Who the surface is for. The guardian's targets are at least 48dp; the child's at least 64dp and
/// her cards are rounder (overhaul.css `.ob.child`). Provided by [OliveAudienceScope]; defaults to
/// the guardian shell.
enum OliveAudience {
  guardian(48, 22),
  child(64, 26);

  const OliveAudience(this.minTarget, this.cardRadius);
  final double minTarget;
  final double cardRadius;
}

/// Sets the [OliveAudience] for every Olive component below it.
class OliveAudienceScope extends InheritedWidget {
  const OliveAudienceScope({super.key, required this.audience, required super.child});
  final OliveAudience audience;

  static OliveAudience of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OliveAudienceScope>()?.audience ?? OliveAudience.guardian;

  @override
  bool updateShouldNotify(OliveAudienceScope old) => old.audience != audience;
}

/// The meaning-carrying tones (kit `tone`: ok warn bad info pri accent quiet).
enum OliveTone { pri, ok, warn, bad, info, accent, quiet }

@immutable
class OlivePalette {
  const OlivePalette({
    required this.dark,
    required this.bg, required this.surface, required this.surface2, required this.surface3,
    required this.line, required this.edge, required this.ink, required this.ink2, required this.ink3,
    required this.pri, required this.priD, required this.priC, required this.priC2,
    required this.onPri, required this.onPriC, required this.accent, required this.accentC,
    required this.ok, required this.okC, required this.warn, required this.warnC,
    required this.bad, required this.badC, required this.info, required this.infoC,
    required this.dpMorning, required this.dpDay, required this.dpAfternoon,
    required this.dpEvening, required this.dpBed, required this.dpNight,
    required this.shadowTint,
    this.elevations,
  });

  final bool dark;
  final Color bg, surface, surface2, surface3, line, edge, ink, ink2, ink3;
  final Color pri, priD, priC, priC2, onPri, onPriC, accent, accentC;
  final Color ok, okC, warn, warnC, bad, badC, info, infoC;
  final Color dpMorning, dpDay, dpAfternoon, dpEvening, dpBed, dpNight;
  final Color shadowTint;
  /// The generated layered shadows, when the design tokens supply them; else [shadow] derives them.
  final List<List<BoxShadow>>? elevations;

  /// The palette of the nearest [Theme].
  static OlivePalette of(BuildContext context) => OlivePalette.fromTheme(Theme.of(context));

  /// Maps a [ThemeData] (as built by buildThemeData) onto the kit's variable names.
  factory OlivePalette.fromTheme(ThemeData theme) {
    final s = theme.colorScheme;
    final dark = s.brightness == Brightness.dark;
    final sem = theme.extension<OliveSemantic>() ?? (dark ? OliveSemantic.dark : OliveSemantic.light);
    // Light: cards are the lightest layer and wells are darker. Dark: cards are lifted above the page.
    final surface = dark ? s.surfaceContainer : s.surfaceContainerLowest;
    final surface2 = dark ? s.surfaceContainerHigh : s.surfaceContainerLow;
    final surface3 = dark ? s.surfaceContainerHighest : s.surfaceContainerHigh;
    final tk = theme.extension<OliveTokens>();
    if (tk != null) {
      // The generated prototype tokens (feat/design-parity-tokens): exact kit colours and shadows.
      return OlivePalette(
        dark: dark,
        bg: tk.bg, surface: tk.surface, surface2: tk.surface2, surface3: tk.surface3,
        line: tk.line, edge: tk.edge, ink: tk.ink, ink2: tk.ink2, ink3: tk.ink3,
        pri: tk.pri, priD: tk.priD, priC: tk.priC, priC2: tk.priC2,
        onPri: tk.role(DesignRole.onPri), onPriC: tk.onPriC, accent: tk.accent, accentC: tk.accentC,
        ok: sem.ok, okC: sem.okContainer, warn: sem.warn, warnC: sem.warnContainer,
        bad: s.error, badC: s.errorContainer, info: sem.info, infoC: sem.infoContainer,
        dpMorning: sem.dayMorning, dpDay: sem.daySchool, dpAfternoon: sem.dayAfternoon,
        dpEvening: sem.dayEvening, dpBed: sem.dayBedtime, dpNight: sem.dayNight,
        shadowTint: dark ? Colors.black : Color.alphaBlend(tk.pri.withValues(alpha: 0.4), Colors.black),
        elevations: tk.elevations,
      );
    }
    final pri = s.primary;
    // The kit's warm accent is the primary hue turned 28 degrees (kit.js OB.theme: H(h+28, ...)), not a
    // Material tertiary, so scenes keep their warm sun and flowers in every palette.
    final hsl = HSLColor.fromColor(pri);
    final hue = (hsl.hue + 28) % 360;
    final accent = HSLColor.fromAHSL(1, hue, dark ? 0.60 : 0.62, dark ? 0.66 : 0.58).toColor();
    final accentC = HSLColor.fromAHSL(1, hue, dark ? 0.40 : 0.70, dark ? 0.26 : 0.90).toColor();
    return OlivePalette(
      dark: dark,
      bg: s.surface, surface: surface, surface2: surface2, surface3: surface3,
      line: s.outlineVariant, edge: s.outline,
      ink: s.onSurface, ink2: s.onSurfaceVariant,
      ink3: Color.lerp(s.onSurfaceVariant, s.surface, dark ? 0.1 : 0.12)!,
      pri: pri,
      priD: Color.lerp(pri, Colors.black, dark ? 0.14 : 0.32)!,
      priC: s.primaryContainer,
      priC2: Color.lerp(s.primaryContainer, pri, 0.28)!,
      onPri: s.onPrimary, onPriC: s.onPrimaryContainer,
      accent: accent, accentC: accentC,
      ok: sem.ok, okC: sem.okContainer, warn: sem.warn, warnC: sem.warnContainer,
      bad: s.error, badC: s.errorContainer, info: sem.info, infoC: sem.infoContainer,
      dpMorning: sem.dayMorning, dpDay: sem.daySchool, dpAfternoon: sem.dayAfternoon,
      dpEvening: sem.dayEvening, dpBed: sem.dayBedtime, dpNight: sem.dayNight,
      shadowTint: dark ? Colors.black : Color.alphaBlend(pri.withValues(alpha: 0.4), Colors.black),
    );
  }

  /// Resolves a token used by the generated art.
  Color tok(OTok t) => switch (t) {
        OTok.bg => bg, OTok.surface => surface, OTok.surface2 => surface2, OTok.surface3 => surface3,
        OTok.line => line, OTok.edge => edge, OTok.ink => ink, OTok.ink2 => ink2, OTok.ink3 => ink3,
        OTok.pri => pri, OTok.priD => priD, OTok.priC => priC, OTok.priC2 => priC2,
        OTok.onPri => onPri, OTok.onPriC => onPriC, OTok.accent => accent, OTok.accentC => accentC,
        OTok.ok => ok, OTok.okC => okC, OTok.warn => warn, OTok.warnC => warnC,
        OTok.bad => bad, OTok.badC => badC, OTok.info => info, OTok.infoC => infoC,
        OTok.dpMorning => dpMorning, OTok.dpDay => dpDay, OTok.dpAfternoon => dpAfternoon,
        OTok.dpEvening => dpEvening, OTok.dpBed => dpBed, OTok.dpNight => dpNight,
      };

  /// Foreground for a tone (kit `.chip.ok { color: var(--ok) }`).
  Color toneFg(OliveTone t) => switch (t) {
        OliveTone.pri => onPriC, OliveTone.ok => ok, OliveTone.warn => warn, OliveTone.bad => bad,
        OliveTone.info => info, OliveTone.accent => ink, OliveTone.quiet => ink2,
      };

  /// Tinted background for a tone (kit `okC`, `warnC` ...).
  Color toneBg(OliveTone t) => switch (t) {
        OliveTone.pri => priC, OliveTone.ok => okC, OliveTone.warn => warnC, OliveTone.bad => badC,
        OliveTone.info => infoC, OliveTone.accent => accentC, OliveTone.quiet => surface3,
      };

  /// Strong accent for a tone (progress fills, timeline rails, schedule block edges).
  Color toneEdge(OliveTone t) => switch (t) {
        OliveTone.pri => pri, OliveTone.ok => ok, OliveTone.warn => warn, OliveTone.bad => bad,
        OliveTone.info => info, OliveTone.accent => accent, OliveTone.quiet => edge,
      };

  /// Elevation 0 (hairline) to 3 (modal). Tinted, never pure black in light mode (kit --shadow0..3).
  List<BoxShadow> shadow(int level) {
    final e = elevations;
    if (e != null) return e[level.clamp(0, 3)];
    Color c(double a) => shadowTint.withValues(alpha: dark ? (a * 4).clamp(0.0, 0.7) : a);
    switch (level) {
      case 0:
        return [BoxShadow(color: c(0.05), blurRadius: 1, offset: const Offset(0, 1))];
      case 1:
        return [
          BoxShadow(color: c(0.06), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: c(0.08), blurRadius: 14, spreadRadius: -2, offset: const Offset(0, 5)),
        ];
      case 2:
        return [
          BoxShadow(color: c(0.07), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: c(0.10), blurRadius: 16, spreadRadius: -4, offset: const Offset(0, 8)),
          BoxShadow(color: c(0.16), blurRadius: 40, spreadRadius: -8, offset: const Offset(0, 22)),
        ];
      default:
        return [
          BoxShadow(color: c(0.08), blurRadius: 4, offset: const Offset(0, 2)),
          BoxShadow(color: c(0.18), blurRadius: 30, spreadRadius: -6, offset: const Offset(0, 16)),
          BoxShadow(color: c(0.30), blurRadius: 70, spreadRadius: -14, offset: const Offset(0, 36)),
        ];
    }
  }

  @override
  bool operator ==(Object other) => other is OlivePalette && other.dark == dark && other.pri == pri &&
      other.priC == priC && other.surface == surface && other.accent == accent && other.ink == ink &&
      other.bg == bg && other.surface2 == surface2 && other.surface3 == surface3;

  @override
  int get hashCode => Object.hash(dark, pri, priC, surface, accent, ink, bg, surface2, surface3);
}

/// Radius ladder of the kit (--r0..--r5), anchored on [AppRadius].
abstract final class OliveRadius {
  static const double r0 = 8;
  static const double r1 = AppRadius.md;
  static const double r2 = AppRadius.lg;
  static const double r3 = AppRadius.xl;
  static const double r4 = AppRadius.sheet;
  static const double r5 = 34;
  /// Fields, buttons and segmented controls (kit 15).
  static const double field = 15;
}

/// Motion durations of the kit (--d-press, --d-fast, --d-base, --d-slow), all through the existing
/// [motionDuration] helper so reduced motion (OS or guardian setting) collapses them to zero.
abstract final class OliveTiming {
  static Duration press(BuildContext c) => motionDuration(c, 40);
  static Duration fast(BuildContext c) => motionDuration(c, 120);
  static Duration base(BuildContext c) => motionDuration(c, 220);
  static Duration slow(BuildContext c) => motionDuration(c, 340);
  /// The kit's --ease-out and --ease-spring (overshoot under 6%).
  static const Curve easeOut = Cubic(0.2, 0.8, 0.2, 1);
  static const Curve spring = Cubic(0.34, 1.12, 0.64, 1);
}

/// The kit type scale (overhaul.css `.t-display .t-title .t-head .t-body .t-cap .t-label .t-mono`),
/// built on the theme's own text theme so the fonts follow theme_data.dart.
abstract final class OliveText {
  static TextStyle _display(BuildContext c, double size, double h, double track, Color color) =>
      Theme.of(c).textTheme.titleLarge!.copyWith(fontSize: size, height: h, letterSpacing: track * size, color: color);

  static TextStyle _body(BuildContext c, double size, double h, Color color, {FontWeight w = FontWeight.w400}) =>
      Theme.of(c).textTheme.bodyMedium!.copyWith(fontSize: size, height: h, color: color, fontWeight: w);

  static TextStyle display(BuildContext c, {Color? color}) =>
      _display(c, 34, 1.0, -0.035, color ?? OlivePalette.of(c).ink);
  static TextStyle title(BuildContext c, {Color? color}) =>
      _display(c, 22, 1.08, -0.022, color ?? OlivePalette.of(c).ink);
  static TextStyle head(BuildContext c, {Color? color}) =>
      _display(c, 17, 1.2, -0.012, color ?? OlivePalette.of(c).ink);
  static TextStyle big(BuildContext c, {Color? color}) =>
      _display(c, 30, 1.05, -0.03, color ?? OlivePalette.of(c).ink);
  static TextStyle body(BuildContext c, {Color? color, FontWeight weight = FontWeight.w400}) =>
      _body(c, 15, 1.4, color ?? OlivePalette.of(c).ink, w: weight);
  static TextStyle strong(BuildContext c, {Color? color, double size = 14.5}) =>
      _body(c, size, 1.25, color ?? OlivePalette.of(c).ink, w: FontWeight.w700);
  static TextStyle cap(BuildContext c, {Color? color}) =>
      _body(c, 12.5, 1.35, color ?? OlivePalette.of(c).ink3);
  /// Small caps label (kit `.t-label`, a mono face). The app bundles no mono face, so this is the body
  /// face with wide tracking and tabular figures.
  static TextStyle label(BuildContext c, {Color? color}) => _body(c, 10.5, 1.2, color ?? OlivePalette.of(c).ink3,
      w: FontWeight.w600).copyWith(letterSpacing: 0.9, fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle mono(BuildContext c, {Color? color, double size = 13}) => _body(c, size, 1.3, color ?? OlivePalette.of(c).ink,
      w: FontWeight.w600).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle tnum(TextStyle s) => s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

/// Spacing ladder of the kit (--sp1..--sp6), anchored on [AppSpacing].
abstract final class OliveSpace {
  static const double sp1 = AppSpacing.xs;
  static const double sp2 = AppSpacing.sm;
  static const double sp3 = AppSpacing.md;
  static const double sp4 = AppSpacing.lg;
  static const double sp5 = AppSpacing.xl;
  static const double sp6 = AppSpacing.xxl;
}
