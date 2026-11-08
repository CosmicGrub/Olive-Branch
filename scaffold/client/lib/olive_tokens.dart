// No longer UNVERIFIED — verified by CI (test/design_parity_test.dart).
// OLIVE BRANCH — the prototype's design tokens, as a Flutter ThemeExtension.
//
// The prototype (docs/superpowers/mockups/live: kit.js + overhaul.css) is the REFERENCE; the real
// app must match it (docs/superpowers/parity/PARITY.md). Flutter's ColorScheme has no slot for
// most of the prototype's roles (the hairline, the control edge, tertiary ink, the hero gradient
// stops, the layered elevation shadows, the mono label style...), so they live here, read from
// the GENERATED design_tokens_generated.dart and never retyped.
//
//   final t = OliveTokens.of(context);
//   Container(decoration: BoxDecoration(color: t.surface, border: Border.all(color: t.line),
//       boxShadow: t.elevation1));
//
// Pure data: nothing here animates, reads a clock, or touches the network.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'design_tokens_generated.dart';

const String kBodyFont = 'AtkinsonHyperlegible';
const String kDisplayFont = 'BricolageGrotesque';
/// The prototype's label/mono face. NOT bundled yet (see PARITY.md, open decision): until the
/// font asset is added the platform monospace is used via [kMonoFallback].
const String kMonoFont = 'JetBrainsMono';
const List<String> kMonoFallback = ['RobotoMono', 'Consolas', 'Menlo', 'monospace'];

Color _c(int argb) => Color(argb);

/// The generated colour for one role, palette and mode.
Color designColor(DesignPalette p, DesignMode m, DesignRole r) => _c(kDesignColors[p]![m]![r]!);

/// A protected colour (ok/warn/bad/info and the day-parts): identical in every palette.
Color designSemantic(DesignMode m, DesignSemantic s) => _c(kDesignSemantic[m]![s]!);

/// One CSS shadow level as Flutter [BoxShadow]s. Inset layers cannot be drawn by BoxShadow and
/// are skipped (the kit uses them only for a 1px inner highlight).
List<BoxShadow> designShadows(DesignPalette p, DesignMode m, int level) => [
      for (final s in kDesignElevation[p]![m]![level])
        if (!s.inset)
          BoxShadow(color: _c(s.color), offset: Offset(s.dx, s.dy), blurRadius: s.blur, spreadRadius: s.spread),
    ];

/// A [TextStyle] from the kit's type scale. [color] is applied by the caller's theme.
TextStyle designTextStyle(String name, {Color? color}) {
  final s = kDesignType[name]!;
  final family = switch (s.family) { 'display' => kDisplayFont, 'mono' => kMonoFont, _ => kBodyFont };
  return TextStyle(
    fontFamily: family,
    fontFamilyFallback: s.family == 'mono' ? kMonoFallback : null,
    fontSize: s.size,
    height: s.lineHeight,
    letterSpacing: s.letterSpacingEm * s.size,
    fontWeight: _weight(s.weight),
    // Bricolage Grotesque is a variable font: ask for the exact weight, not the nearest bucket.
    fontVariations: s.family == 'display' ? [FontVariation('wght', s.weight.toDouble())] : null,
    color: color,
  );
}

FontWeight _weight(int w) => FontWeight.values.firstWhere((f) => f.value == w, orElse: () => FontWeight.w400);

/// Motion tokens: consequence only, under 400 ms, overshoot under 6 percent.
class OliveMotion {
  const OliveMotion._();
  static Duration get press => Duration(milliseconds: kDesignDurationsMs['press']!);
  static Duration get fast => Duration(milliseconds: kDesignDurationsMs['fast']!);
  static Duration get base => Duration(milliseconds: kDesignDurationsMs['base']!);
  static Duration get slow => Duration(milliseconds: kDesignDurationsMs['slow']!);
  static Cubic _curve(String n) {
    final e = kDesignEasings[n]!;
    return Cubic(e[0], e[1], e[2], e[3]);
  }
  static Cubic get easeOut => _curve('out');
  static Cubic get easeSpring => _curve('spring');
  static Cubic get easeIn => _curve('in');

  /// Honours the system reduce-motion setting the way the prototype's
  /// prefers-reduced-motion block does: every animation collapses.
  static Duration resolve(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

/// The prototype's roles that ColorScheme cannot hold, plus the full role set for parity.
@immutable
class OliveTokens extends ThemeExtension<OliveTokens> {
  const OliveTokens({
    required this.palette,
    required this.mode,
    required this.roles,
    required this.sheen,
    required this.elevations,
  });

  /// Builds the tokens for a palette and mode from the generated data.
  factory OliveTokens.forTheme(DesignPalette palette, DesignMode mode) => OliveTokens(
        palette: palette,
        mode: mode,
        roles: {for (final e in kDesignColors[palette]![mode]!.entries) e.key: _c(e.value)},
        sheen: kDesignSheen[mode]!,
        elevations: [for (var i = 0; i < 4; i++) designShadows(palette, mode, i)],
      );

  final DesignPalette palette;
  final DesignMode mode;
  /// Every generated role for this palette and mode (parity tests walk this map).
  final Map<DesignRole, Color> roles;
  final double sheen;
  /// Elevation 0 (hairline) to 3 (modal), as drawable shadows.
  final List<List<BoxShadow>> elevations;

  static OliveTokens of(BuildContext context) =>
      Theme.of(context).extension<OliveTokens>() ?? OliveTokens.forTheme(DesignPalette.olive, DesignMode.light);

  Color role(DesignRole r) => roles[r]!;
  Color get bg => role(DesignRole.bg);
  Color get surface => role(DesignRole.surface);
  Color get surface2 => role(DesignRole.surface2);
  Color get surface3 => role(DesignRole.surface3);
  /// Decorative hairline (cards, dividers). Not for control edges.
  Color get line => role(DesignRole.line);
  /// Control border / unchecked box / off track; at least 3:1 on bg and surfaces.
  Color get edge => role(DesignRole.edge);
  Color get track => role(DesignRole.track);
  Color get ink => role(DesignRole.ink);
  Color get ink2 => role(DesignRole.ink2);
  /// Tertiary text; still 4.5:1 on every surface.
  Color get ink3 => role(DesignRole.ink3);
  Color get pri => role(DesignRole.pri);
  Color get priD => role(DesignRole.priD);
  Color get priC => role(DesignRole.priC);
  Color get priC2 => role(DesignRole.priC2);
  Color get onPriC => role(DesignRole.onPriC);
  Color get accent => role(DesignRole.accent);
  Color get accentC => role(DesignRole.accentC);
  Color get onAccent => role(DesignRole.onAccent);
  Color get focus => role(DesignRole.focus);
  /// Inner top highlight colour.
  Color get hiC => role(DesignRole.hiC);
  Color get hero1 => role(DesignRole.hero1);
  Color get hero2 => role(DesignRole.hero2);

  List<BoxShadow> get elevation0 => elevations[0];
  List<BoxShadow> get elevation1 => elevations[1];
  List<BoxShadow> get elevation2 => elevations[2];
  List<BoxShadow> get elevation3 => elevations[3];

  /// The hero card's gradient (155 degrees, hero1 to hero2).
  LinearGradient get heroGradient =>
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [hero1, hero2]);

  // Type scale entries Material's TextTheme has no slot for.
  TextStyle get label => designTextStyle('label', color: ink3);
  TextStyle get mono => designTextStyle('mono', color: ink);
  TextStyle get big => designTextStyle('big', color: ink);
  TextStyle get caption => designTextStyle('cap', color: ink3);
  TextStyle get rowTitle => designTextStyle('rowTitle', color: ink);
  TextStyle get rowSub => designTextStyle('rowSub', color: ink3);

  /// The focus ring: kDesignFocusWidth thick, kDesignFocusOffset away from the control.
  BorderSide get focusSide => BorderSide(color: focus, width: kDesignFocusWidth);

  @override
  OliveTokens copyWith({DesignPalette? palette, DesignMode? mode, Map<DesignRole, Color>? roles, double? sheen,
          List<List<BoxShadow>>? elevations}) =>
      OliveTokens(
          palette: palette ?? this.palette, mode: mode ?? this.mode, roles: roles ?? this.roles,
          sheen: sheen ?? this.sheen, elevations: elevations ?? this.elevations);

  /// A theme swap crossfades the colours; shadows follow the nearer side.
  @override
  OliveTokens lerp(ThemeExtension<OliveTokens>? other, double t) {
    if (other is! OliveTokens) return this;
    return OliveTokens(
      palette: t < 0.5 ? palette : other.palette,
      mode: t < 0.5 ? mode : other.mode,
      roles: {for (final e in roles.entries) e.key: Color.lerp(e.value, other.roles[e.key], t)!},
      sheen: sheen + (other.sheen - sheen) * t,
      elevations: t < 0.5 ? elevations : other.elevations,
    );
  }

  /// Contrast helper for tests and for components that must pick a legible ink.
  static double contrast(Color a, Color b) {
    double lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    double lum(Color c) => 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    final x = lum(a), y = lum(b);
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }
}
