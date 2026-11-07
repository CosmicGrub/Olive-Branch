// OLIVE BRANCH — the refined ThemeData. The overhaul's design foundation
// (docs/superpowers/mockups/overhaul): one place that turns an [AppTheme]
// (palette x brightness, theme.dart) into a complete, premium Material theme,
// so every existing screen inherits the new look without per-screen edits.
//
// What changes versus the old `ThemeData(colorScheme: ..., useMaterial3: true)`:
//   * Type: Bricolage Grotesque (display/headline/title) and Atkinson
//     Hyperlegible (body/label), bundled in assets/fonts so the kiosk never
//     needs the network. Atkinson was designed for legibility; the product's
//     accessibility story (§8.4) is the reason it is the body face.
//   * Shape: softer radii (AppRadius.xl for cards, 15 for buttons and fields,
//     AppRadius.sheet for sheets and dialogs).
//   * Depth: two tinted elevations, never pure black, never a heavy drop.
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
import 'theme.dart';

const String kBodyFont = 'AtkinsonHyperlegible';
const String kDisplayFont = 'BricolageGrotesque';

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

  final Color ok, okContainer, warn, warnContainer, info, infoContainer;
  final Color dayMorning, daySchool, dayAfternoon, dayEvening, dayBedtime, dayNight;
  /// The band that means "you can both talk right now".
  final Color overlap;

  static const light = OliveSemantic(
    ok: Color(0xFF237A52), okContainer: Color(0xFFDCF3E6),
    warn: Color(0xFF8F6100), warnContainer: Color(0xFFFCEFCF),
    info: Color(0xFF245F9C), infoContainer: Color(0xFFDCEAFA),
    dayMorning: Color(0xFFF2BD4E), daySchool: Color(0xFF78B6E8),
    dayAfternoon: Color(0xFF88C98F), dayEvening: Color(0xFFE59A6B),
    dayBedtime: Color(0xFF7D84C9), dayNight: Color(0xFF3E4580),
    overlap: Color(0xFF237A52),
  );

  static const dark = OliveSemantic(
    ok: Color(0xFF6CCF9D), okContainer: Color(0xFF12301F),
    warn: Color(0xFFECC15C), warnContainer: Color(0xFF34290C),
    info: Color(0xFF8BBDF0), infoContainer: Color(0xFF122A44),
    dayMorning: Color(0xFFE9B955), daySchool: Color(0xFF6FA9DE),
    dayAfternoon: Color(0xFF7FC08A), dayEvening: Color(0xFFDC8F62),
    dayBedtime: Color(0xFF8D93D6), dayNight: Color(0xFF4A5399),
    overlap: Color(0xFF6CCF9D),
  );

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

/// The refined text theme. Display, headline and title use the display face at
/// a heavy weight; everything people read in sentences uses the body face.
TextTheme _textTheme(ColorScheme s) {
  TextStyle display(double size, {double h = 1.1, double w = 800}) => TextStyle(
      fontFamily: kDisplayFont, fontSize: size, height: h, letterSpacing: -0.01 * size,
      fontVariations: [FontVariation('wght', w)], fontWeight: FontWeight.w800);
  TextStyle body(double size, {double h = 1.4, FontWeight w = FontWeight.w400}) =>
      TextStyle(fontFamily: kBodyFont, fontSize: size, height: h, fontWeight: w);
  return TextTheme(
    displayLarge: display(44), displayMedium: display(36), displaySmall: display(30),
    headlineLarge: display(28), headlineMedium: display(24), headlineSmall: display(20),
    titleLarge: display(22), titleMedium: display(17, h: 1.2), titleSmall: display(15, h: 1.2),
    bodyLarge: body(16), bodyMedium: body(14.5), bodySmall: body(12.5, h: 1.35),
    labelLarge: body(15, h: 1.2, w: FontWeight.w700),
    labelMedium: body(13, h: 1.2, w: FontWeight.w700),
    labelSmall: body(11, h: 1.2, w: FontWeight.w700),
  ).apply(bodyColor: s.onSurface, displayColor: s.onSurface);
}

/// THE theme. Pure: the same [AppTheme] always yields an equal ThemeData.
ThemeData buildThemeData(AppTheme theme) {
  final s = colorSchemeFor(theme);
  final dark = s.brightness == Brightness.dark;
  final text = _textTheme(s);
  final hairline = s.outlineVariant.withValues(alpha: 0.7);
  final shadow = Color.alphaBlend(s.primary.withValues(alpha: 0.35), Colors.black)
      .withValues(alpha: dark ? 0.55 : 0.16);
  const field = 15.0;
  RoundedRectangleBorder shape(double r, {BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: side);

  return ThemeData(
    useMaterial3: true,
    colorScheme: s,
    fontFamily: kBodyFont,
    textTheme: text,
    scaffoldBackgroundColor: s.surface,
    extensions: <ThemeExtension<dynamic>>[dark ? OliveSemantic.dark : OliveSemantic.light],
    cardTheme: CardThemeData(
      color: s.surfaceContainerLowest, surfaceTintColor: Colors.transparent,
      shadowColor: shadow, elevation: 1.5, margin: EdgeInsets.zero,
      shape: shape(AppRadius.xl, side: BorderSide(color: hairline))),
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface, foregroundColor: s.onSurface, surfaceTintColor: Colors.transparent,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false, titleTextStyle: text.titleLarge),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size(64, 46), shape: shape(field), textStyle: text.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: 20))),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
      minimumSize: const Size(64, 46), shape: shape(field), textStyle: text.labelLarge,
      elevation: 0, backgroundColor: s.primaryContainer, foregroundColor: s.onPrimaryContainer)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      minimumSize: const Size(64, 46), shape: shape(field), textStyle: text.labelLarge,
      side: BorderSide(color: s.outline, width: 1.5))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      minimumSize: const Size(48, 44), shape: shape(field), textStyle: text.labelLarge)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(44, 44))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: s.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(field), borderSide: BorderSide(color: s.outlineVariant, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(field), borderSide: BorderSide(color: s.outlineVariant, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(field), borderSide: BorderSide(color: s.primary, width: 2))),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(), side: BorderSide.none, backgroundColor: s.surfaceContainerHigh,
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
      behavior: SnackBarBehavior.floating, shape: shape(AppRadius.md),
      backgroundColor: s.inverseSurface, contentTextStyle: text.bodyMedium?.copyWith(color: s.onInverseSurface)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: s.surfaceContainerLowest.withValues(alpha: 0.92), surfaceTintColor: Colors.transparent,
      indicatorColor: s.primaryContainer, indicatorShape: shape(AppRadius.lg), elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall)),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
      shape: WidgetStatePropertyAll(shape(AppRadius.md)))),
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
