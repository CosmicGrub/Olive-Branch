// No longer UNVERIFIED — verified by CI (theme_data_test.dart, design_parity_test.dart).
// OLIVE BRANCH — the refined ThemeData. The overhaul's design foundation
// (docs/superpowers/mockups/live): one place that turns an [AppTheme]
// (palette x brightness, theme.dart) into a complete, premium Material theme,
// so every existing screen inherits the new look without per-screen edits.
//
// PARITY RULE (docs/superpowers/parity/PARITY.md): the prototype is the reference and Flutter
// must match it. Nothing in this file invents a colour, size, radius or duration: they all come
// from design_tokens_generated.dart (generated from the prototype's kit.js + overhaul.css by
// tools/gen-design-tokens.mjs), and test/design_parity_test.dart fails if this theme drifts.
//
//   * Type: Bricolage Grotesque (display/headline/title) and Atkinson
//     Hyperlegible (body/label), bundled in assets/fonts so the kiosk never
//     needs the network. The prototype's mono label face (JetBrains Mono) is
//     not bundled yet; see olive_tokens.dart.
//   * Shape: the prototype's radii (22 cards, 15 controls, 28 sheets and dialogs, 99 chips).
//   * Depth: the prototype's layered, hue-tinted shadows live on [OliveTokens.elevations];
//     Material's own single-layer shadow is tinted to match where a Card is used.
//   * Protected colours: [OliveSemantic] carries the colours that MEAN
//     something (success, warning, day-part bands, the overlap band). They are
//     fixed per brightness and never taken from a palette, so §8.6.2's rule —
//     her colour, or a theme, can never land on something that carries
//     meaning — holds by construction.
//
// Nothing here is animated, and nothing reads a clock: theme data is a pure
// function of its input.
import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'design_tokens_generated.dart';
import 'olive_tokens.dart';
import 'theme.dart';

export 'olive_tokens.dart' show kBodyFont, kDisplayFont, kMonoFont, OliveTokens, OliveMotion;

/// Colours that carry meaning. Fixed per brightness; never palette-derived.
@immutable
class OliveSemantic extends ThemeExtension<OliveSemantic> {
  const OliveSemantic({
    required this.ok, required this.okContainer,
    required this.warn, required this.warnContainer,
    required this.info, required this.infoContainer,
    required this.dayMorning, required this.daySchool, required this.dayAfternoon,
    required this.dayEvening, required this.dayBedtime, required this.dayNight,
    required this.overlap,
  });

  /// Reads the protected set from the generated tokens (the prototype's own values).
  factory OliveSemantic.forMode(DesignMode m) {
    Color c(DesignSemantic s) => designSemantic(m, s);
    return OliveSemantic(
      ok: c(DesignSemantic.ok), okContainer: c(DesignSemantic.okC),
      warn: c(DesignSemantic.warn), warnContainer: c(DesignSemantic.warnC),
      info: c(DesignSemantic.info), infoContainer: c(DesignSemantic.infoC),
      dayMorning: c(DesignSemantic.dpMorning), daySchool: c(DesignSemantic.dpDay),
      dayAfternoon: c(DesignSemantic.dpAfternoon), dayEvening: c(DesignSemantic.dpEvening),
      dayBedtime: c(DesignSemantic.dpBed), dayNight: c(DesignSemantic.dpNight),
      overlap: c(DesignSemantic.ok),
    );
  }

  final Color ok, okContainer, warn, warnContainer, info, infoContainer;
  final Color dayMorning, daySchool, dayAfternoon, dayEvening, dayBedtime, dayNight;
  /// The band that means "you can both talk right now".
  final Color overlap;

  static final light = OliveSemantic.forMode(DesignMode.light);
  static final dark = OliveSemantic.forMode(DesignMode.dark);

  @override
  OliveSemantic copyWith({Color? ok, Color? okContainer, Color? warn, Color? warnContainer,
      Color? info, Color? infoContainer, Color? dayMorning, Color? daySchool,
      Color? dayAfternoon, Color? dayEvening, Color? dayBedtime, Color? dayNight, Color? overlap}) =>
    OliveSemantic(
      ok: ok ?? this.ok, okContainer: okContainer ?? this.okContainer,
      warn: warn ?? this.warn, warnContainer: warnContainer ?? this.warnContainer,
      info: info ?? this.info, infoContainer: infoContainer ?? this.infoContainer,
      dayMorning: dayMorning ?? this.dayMorning, daySchool: daySchool ?? this.daySchool,
      dayAfternoon: dayAfternoon ?? this.dayAfternoon, dayEvening: dayEvening ?? this.dayEvening,
      dayBedtime: dayBedtime ?? this.dayBedtime, dayNight: dayNight ?? this.dayNight,
      overlap: overlap ?? this.overlap);

  /// Semantic colours do not interpolate toward a palette: a theme swap
  /// crossfades the palette, and these stay exactly where they are.
  @override
  OliveSemantic lerp(ThemeExtension<OliveSemantic>? other, double t) =>
      other is OliveSemantic ? (t < 0.5 ? this : other) : this;
}

/// The refined text theme, mapped from the prototype's type scale
/// (display / big / title / head / cardHead / body / cap / button / pill).
/// Display, headline and title use the display face at a heavy weight; everything people read
/// in sentences uses the body face.
TextTheme _textTheme(ColorScheme s, OliveTokens t) {
  TextStyle st(String name) => designTextStyle(name);
  return TextTheme(
    displayLarge: st('display'), displayMedium: st('big'), displaySmall: st('title'),
    headlineLarge: st('title'), headlineMedium: st('title'), headlineSmall: st('head'),
    titleLarge: st('title'), titleMedium: st('head'), titleSmall: st('cardHead'),
    bodyLarge: st('body'), bodyMedium: st('body'), bodySmall: st('cap'),
    labelLarge: st('button'), labelMedium: st('buttonSm'), labelSmall: st('pillSm'),
  ).apply(bodyColor: s.onSurface, displayColor: s.onSurface).copyWith(
        // The prototype's caption is tertiary ink (still 4.5:1 on every surface).
        bodySmall: st('cap').copyWith(color: t.ink3),
      );
}

/// THE theme. Pure: the same [AppTheme] always yields an equal ThemeData.
ThemeData buildThemeData(AppTheme theme) {
  final s = colorSchemeFor(theme);
  final p = designPaletteOf(theme.palette), m = designModeOf(theme.brightness);
  final dark = s.brightness == Brightness.dark;
  final tokens = OliveTokens.forTheme(p, m);
  final text = _textTheme(s, tokens);
  final hairline = tokens.line;
  // Material's single-layer card shadow, tinted like the prototype's (ink in light, black in dark).
  final shadow = (dark ? Colors.black : tokens.ink).withValues(alpha: dark ? 0.55 : 0.16);
  final comp = kDesignComponents;
  final field = comp['field']!['radius']!;
  final controlH = comp['button']!['minHeight']!;
  final ghostW = comp['button']!['borderWidthGhost']!;
  final focusSide = tokens.focusSide;
  RoundedRectangleBorder shape(double r, {BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: side);
  // The prototype's focus ring: 3px, in the focus role. Keyboard / switch-access focus only.
  WidgetStateProperty<BorderSide?> ring(BorderSide rest) => WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused) ? focusSide : rest);

  return ThemeData(
    useMaterial3: true,
    colorScheme: s,
    fontFamily: kBodyFont,
    textTheme: text,
    scaffoldBackgroundColor: s.surface,
    focusColor: tokens.focus.withValues(alpha: 0.16),
    extensions: <ThemeExtension<dynamic>>[dark ? OliveSemantic.dark : OliveSemantic.light, tokens],
    cardTheme: CardThemeData(
      color: s.surfaceContainerLowest, surfaceTintColor: Colors.transparent,
      shadowColor: shadow, elevation: 1.5, margin: EdgeInsets.zero,
      shape: shape(AppRadius.xl, side: BorderSide(color: hairline))),
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface, foregroundColor: s.onSurface, surfaceTintColor: Colors.transparent,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false, titleTextStyle: text.titleLarge),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: Size(64, controlH), shape: shape(field), textStyle: text.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: 18)).copyWith(side: ring(BorderSide.none))),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      minimumSize: Size(64, controlH), shape: shape(field), textStyle: text.labelLarge,
      elevation: 0, backgroundColor: s.primaryContainer, foregroundColor: s.onPrimaryContainer)
        .copyWith(side: ring(BorderSide.none))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      minimumSize: Size(64, controlH), shape: shape(field), textStyle: text.labelLarge,
      foregroundColor: s.onSurface).copyWith(side: ring(BorderSide(color: s.outline, width: ghostW)))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      minimumSize: const Size(48, 48), shape: shape(field), textStyle: text.labelLarge)
        .copyWith(side: ring(BorderSide.none))),
    // §8.4: nothing a hand has to hit is below 48dp (the child's own controls go to 64).
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: s.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: tokens.ink3, fontWeight: FontWeight.w400),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(field), borderSide: BorderSide(color: s.outline, width: comp['field']!['borderWidth']!)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(field), borderSide: BorderSide(color: s.outline, width: comp['field']!['borderWidth']!)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(field), borderSide: BorderSide(color: s.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(field), borderSide: BorderSide(color: s.error, width: comp['field']!['borderWidth']!)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(field), borderSide: BorderSide(color: s.error, width: 2))),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: WidgetStateBorderSide.resolveWith((states) => BorderSide(
          color: states.contains(WidgetState.selected) ? s.primary : s.outline, width: comp['chip']!['borderWidth']!)),
      backgroundColor: s.surfaceContainerLowest, selectedColor: s.primaryContainer,
      labelStyle: text.labelMedium, padding: const EdgeInsets.symmetric(horizontal: 6)),
    listTileTheme: ListTileThemeData(shape: shape(AppRadius.lg), iconColor: s.primary, minVerticalPadding: 10),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surfaceContainerLowest, surfaceTintColor: Colors.transparent,
      shape: shape(AppRadius.sheet), titleTextStyle: text.titleLarge),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surfaceContainerLowest, surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      showDragHandle: true),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating, shape: shape(AppRadius.lg),
      backgroundColor: s.inverseSurface, contentTextStyle: text.bodyMedium?.copyWith(color: s.onInverseSurface)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: s.surfaceContainerLowest.withValues(alpha: 0.88), surfaceTintColor: Colors.transparent,
      indicatorColor: s.primaryContainer, indicatorShape: shape(field), elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(designTextStyle('tabLabel'))),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
      shape: WidgetStatePropertyAll(shape(AppRadius.md)))),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.primary : tokens.track),
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.onPrimary : s.surfaceContainerLowest),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent)),
    checkboxTheme: CheckboxThemeData(
      shape: shape(comp['checkbox']!['radius']!),
      side: WidgetStateBorderSide.resolveWith((st) => st.contains(WidgetState.selected)
          ? BorderSide(color: s.primary, width: comp['checkbox']!['borderWidth']!)
          : BorderSide(color: s.outline, width: comp['checkbox']!['borderWidth']!)),
      fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.primary : s.surfaceContainerLowest),
      checkColor: WidgetStatePropertyAll(s.onPrimary)),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.primary : s.outline)),
    sliderTheme: SliderThemeData(
      trackHeight: comp['sliderTrack']!['height']!, activeTrackColor: s.primary,
      inactiveTrackColor: s.surfaceContainerHigh, thumbColor: s.primary, overlayColor: tokens.focus.withValues(alpha: 0.16)),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: s.primary, linearTrackColor: s.surfaceContainerHigh, linearMinHeight: 8),
    dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      // A crossfade, not a travel: the calm option the motion rules name for
      // still surfaces, and a safe default everywhere else (§8.13.5).
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
