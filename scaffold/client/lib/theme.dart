// OLIVE BRANCH — theme catalog. No longer UNVERIFIED — verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — also manually
// built and run via `flutter analyze` / `flutter test` this session;
// CHANGELOG v0.49.61). MASTERFILE §8.1,
// `docs/superpowers/specs/2026-08-21-intuitivism-visual-foundation-design.md`.
//
// Replaces the app's own stock-template default —
// `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`, sitting unchanged in
// `main.dart`/`main_live.dart` since the very first build — with a real,
// guardian-configurable catalog. Two independent axes, not flat options: a
// PALETTE (hue identity) crossed with a BRIGHTNESS (light/dark), so a new
// palette never needs its own hand-tuned dark variant — `ColorScheme.
// fromSeed(seedColor: ..., brightness: ...)` derives both from one real seed
// color, the same technique the stock default already used for its one
// palette. `classic` keeps `Colors.deepPurple` as an explicit reset/
// escape-hatch option, not a removed one.
//
// Guardian-only, app-wide (not per-child — see the spec's own "explicitly
// out of scope" section), backend-synced (theme_picker_screen.dart writes it,
// main_live.dart's session bootstrap reads it) so the two physical devices a
// family actually uses (Fold5, tablet) render the SAME family "look"
// regardless of which one the child is holding. The child never sees a way
// to reach this — see child_home.dart's own header; nothing in this file is
// imported there.
import 'package:flutter/material.dart';
import 'design_tokens_generated.dart';
import 'olive_tokens.dart' show designColor, designSemantic;

/// Hue identity. See the design spec's own palette table for the intended
/// feel of each — exact seed colors are this file's implementation detail,
/// deliberately left unlocked by the spec.
///
/// `olive` is the brand palette and, as of the overhaul (docs/superpowers/
/// mockups/overhaul), the app's own default. It sits FIRST so the picker lists
/// the brand look first; the wire value is the enum `.name`, so ordering never
/// matters to the server (see toWire's own note on why names, not indexes).
enum ThemePalette { olive, classic, calmModern, warmGrounded, softPlayful, deepCozy, brightBold }

enum ThemeBrightness { light, dark }

/// A real, tiny value type — not a bare (palette, brightness) tuple — so
/// call sites (the picker's own pending-selection state, the ValueNotifier
/// held above MaterialApp) have one thing to pass around and compare.
class AppTheme {
  const AppTheme({required this.palette, required this.brightness});
  final ThemePalette palette;
  final ThemeBrightness brightness;

  AppTheme copyWith({ThemePalette? palette, ThemeBrightness? brightness}) =>
      AppTheme(palette: palette ?? this.palette, brightness: brightness ?? this.brightness);

  @override
  bool operator ==(Object other) =>
      other is AppTheme && other.palette == palette && other.brightness == brightness;

  @override
  int get hashCode => Object.hash(palette, brightness);

  @override
  String toString() => 'AppTheme(${palette.name}, ${brightness.name})';

  /// Wire encoding — matches server/routes.mjs's `theme_palette`/
  /// `theme_brightness` columns exactly (db/migrations/0017_child_theme_
  /// preference.sql), enum `.name` on both sides, never a numeric index
  /// (an index silently renumbers if this enum is ever reordered; a name
  /// does not).
  Map<String, String> toWire() => {'themePalette': palette.name, 'themeBrightness': brightness.name};

  /// FAILS CLOSED, deliberately, the same discipline `verifyKioskPin`'s own
  /// doc comment describes: a null map (no row set yet), an unrecognized
  /// palette/brightness string (a future server value this build predates,
  /// or a malformed response), or a caught fetch exception at the call site
  /// must never produce a half-applied or crashing theme — every one of
  /// those collapses to [defaultAppTheme] (`classic`/`light`, the app's own
  /// former stock look) here, not partway through parsing.
  factory AppTheme.fromWire(Map<String, dynamic>? wire) {
    if (wire == null) return defaultAppTheme;
    final paletteWire = wire['themePalette'];
    final brightnessWire = wire['themeBrightness'];
    final palette = ThemePalette.values
        .where((p) => p.name == paletteWire)
        .firstOrNull;
    final brightness = ThemeBrightness.values
        .where((b) => b.name == brightnessWire)
        .firstOrNull;
    if (palette == null || brightness == null) return defaultAppTheme;
    return AppTheme(palette: palette, brightness: brightness);
  }
}

/// FAIL-CLOSED fallback for an unset backend value or any fetch failure —
/// the app's own former stock look, not a guess. Deliberately NOT
/// `calmModern`: that palette is this catalog's own recommended STARTING
/// POINT for a guardian who has never opened the picker (see
/// theme_picker_screen.dart's own initial pending-selection default) — a
/// soft product opinion about what to suggest, evaluated only client-side,
/// inside a screen a guardian is already looking at. `classic`/`light` is
/// the different, harder guarantee: what actually renders app-wide, on
/// every device, the instant something above this layer goes wrong (no row
/// yet, a 404, a timeout, a malformed body) — the same "fail-crash instead
/// of fail-closed" hazard 0003_session_context.sql's own header warns
/// against, avoided here the same way.
///
/// OVERHAUL: the default is now the brand palette, `olive`/`light`. The
/// fail-closed property this comment describes is unchanged — it is still the
/// one palette every device renders the instant something above this layer
/// goes wrong — only which palette that is. `classic` (the old stock deep
/// purple) stays available as an explicit, real option.
const defaultAppTheme = AppTheme(palette: ThemePalette.olive, brightness: ThemeBrightness.light);

/// The palette's generated name (design_tokens_generated.dart). The enum NAMES match 1:1; the
/// wire value (`.name`) is unchanged.
DesignPalette designPaletteOf(ThemePalette p) => DesignPalette.values.byName(p.name);
DesignMode designModeOf(ThemeBrightness b) => b == ThemeBrightness.dark ? DesignMode.dark : DesignMode.light;

/// The prototype's seed colour per palette (kit.js SEEDS), generated. `classic` is
/// `Colors.deepPurple` verbatim: the stock default this whole catalog replaces, kept as an
/// explicit, real option rather than deleted outright.
Color seedFor(ThemePalette palette) => Color(kDesignSeeds[designPaletteOf(palette)]!);

/// THE real catalog function: 14 `ColorScheme`s (7 palettes x 2 brightnesses).
///
/// PARITY (docs/superpowers/parity/PARITY.md): the prototype is the reference. These are NOT
/// `ColorScheme.fromSeed` derivations any more; every slot is a role of the prototype's own
/// `OB.theme(palette, mode)`, read from the generated tokens, so the real app and the live
/// prototype are the same colours by construction (test/design_parity_test.dart proves it).
///
/// Role -> slot: bg -> surface (the page), surface -> surfaceContainerLowest (cards), surface2 ->
/// surfaceContainer, surface3 -> surfaceContainerHigh/Highest, ink -> onSurface, ink2 ->
/// onSurfaceVariant, edge -> outline (control borders, 3:1), line -> outlineVariant (hairlines),
/// pri/onPri, priC/onPriC -> primary/primaryContainer, accent/accentC -> secondary/
/// secondaryContainer, priD/priC2 -> tertiary/tertiaryContainer, bad/badC -> error/errorContainer.
/// Roles with no slot (ink3, line, track, focus, hero stops, shadows) are on [OliveTokens].
ColorScheme colorSchemeFor(AppTheme theme) {
  final p = designPaletteOf(theme.palette), m = designModeOf(theme.brightness);
  Color r(DesignRole role) => designColor(p, m, role);
  Color sem(DesignSemantic s) => designSemantic(m, s);
  return ColorScheme(
    brightness: m == DesignMode.dark ? Brightness.dark : Brightness.light,
    primary: r(DesignRole.pri), onPrimary: r(DesignRole.onPri),
    primaryContainer: r(DesignRole.priC), onPrimaryContainer: r(DesignRole.onPriC),
    secondary: r(DesignRole.accent), onSecondary: r(DesignRole.onAccent),
    secondaryContainer: r(DesignRole.accentC), onSecondaryContainer: r(DesignRole.ink),
    tertiary: r(DesignRole.priD), onTertiary: r(DesignRole.onPri),
    tertiaryContainer: r(DesignRole.priC2), onTertiaryContainer: r(DesignRole.onPriC),
    error: sem(DesignSemantic.bad), onError: r(DesignRole.onBad),
    errorContainer: sem(DesignSemantic.badC), onErrorContainer: sem(DesignSemantic.bad),
    surface: r(DesignRole.bg), onSurface: r(DesignRole.ink), onSurfaceVariant: r(DesignRole.ink2),
    surfaceDim: r(DesignRole.surface3), surfaceBright: r(DesignRole.surface),
    surfaceContainerLowest: r(DesignRole.surface), surfaceContainerLow: r(DesignRole.bg),
    surfaceContainer: r(DesignRole.surface2), surfaceContainerHigh: r(DesignRole.surface3),
    surfaceContainerHighest: r(DesignRole.surface3),
    outline: r(DesignRole.edge), outlineVariant: r(DesignRole.line),
    shadow: Colors.black, scrim: Colors.black, surfaceTint: r(DesignRole.pri),
    inverseSurface: r(DesignRole.ink), onInverseSurface: r(DesignRole.bg), inversePrimary: r(DesignRole.priC2),
  );
}

/// Human-facing title + one-line blurb per palette — theme_picker_screen.dart's
/// own card content, kept here alongside the catalog itself rather than
/// duplicated at the call site (single source for "what this palette is
/// called and how it's described").
class ThemePaletteMeta {
  const ThemePaletteMeta({required this.title, required this.blurb, required this.icon});
  final String title;
  final String blurb;
  final IconData icon;
}

const Map<ThemePalette, ThemePaletteMeta> themePaletteCatalogue = {
  ThemePalette.olive: ThemePaletteMeta(
      title: 'Olive',
      blurb: 'The brand look — calm olive green. The default.',
      icon: Icons.eco_outlined),
  ThemePalette.classic: ThemePaletteMeta(
      title: 'Classic',
      blurb: 'The original look — a reset, not a downgrade.',
      icon: Icons.circle),
  ThemePalette.calmModern: ThemePaletteMeta(
      title: 'Calm modern',
      blurb: 'Muted teal, soft neutrals. The suggested starting point.',
      icon: Icons.spa_outlined),
  ThemePalette.warmGrounded: ThemePaletteMeta(
      title: 'Warm grounded',
      blurb: 'Terracotta and amber — steady, unhurried.',
      icon: Icons.landscape_outlined),
  ThemePalette.softPlayful: ThemePaletteMeta(
      title: 'Soft playful',
      blurb: 'Coral and peach — the most overtly kid-app option.',
      icon: Icons.celebration_outlined),
  ThemePalette.deepCozy: ThemePaletteMeta(
      title: 'Deep cozy',
      blurb: 'Forest green — richer, evening-friendly, lived-in.',
      icon: Icons.nightlight_outlined),
  ThemePalette.brightBold: ThemePaletteMeta(
      title: 'Bright bold',
      blurb: 'Confident blue — energetic, not pastel.',
      icon: Icons.bolt_outlined),
};

/// A `ValueNotifier<AppTheme>` held above `MaterialApp`
/// (main_live.dart's own `_OliveLiveState`) — the spec's own suggested
/// shape, not a new state-management dependency: this codebase's plain
/// StatefulWidget/setState style, extended by exactly one class. Listening
/// widgets (an `AnimatedBuilder`/`ListenableBuilder` around `MaterialApp`)
/// rebuild `theme:`/`darkTheme:`/`themeMode:` whenever [value] changes —
/// i.e. only on an explicit guardian Apply, never on a timer or any other
/// autonomous trigger (P2/§8.13 — this is a preference, not a game, and a
/// theme swap is real consequence motion, not a loop).
class ThemeController extends ValueNotifier<AppTheme> {
  ThemeController([super.initial = defaultAppTheme]);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
