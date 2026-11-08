// OLIVE BRANCH — how the accessibility settings reach the screens: the scope the
// child's widgets read, the host that installs it, and the three shared helpers
// (reduce motion, roomier reading, target floors) every screen goes through.
// No longer UNVERIFIED — verified by CI (client/test/access_scope_test.dart).
// MASTERFILE §8.4, §8.13, §8.21.
//
// READ-ONLY FOR HER. A child widget can read the settings here and nothing else:
// the one writer is the guardian's screen (access_screen.dart). A widget built
// with no scope above it (every existing test, any screen opened on its own)
// sees [AccessSettings.defaults], which behaves exactly as the app did before
// this file existed.
//
// ONE MOTION HELPER. Every consequence animation in the child's screens takes its
// duration from [motionDuration]. When reduced motion is on, from the OS
// (MediaQuery.disableAnimations) or from the guardian's setting, that is zero:
// the new thing is simply there, an instant crossfade with no travel. No helper
// here starts any motion, and nothing in this file can make something move on its
// own (§8.13: motion follows the finger).
import 'package:flutter/material.dart';

import 'access_settings.dart';
import 'motion_rules.dart';

// So a child screen can take its target floor from here without importing the
// settings model's file by name (her shell has no settings affordance, §8.1, and
// child_no_settings_contract_test.dart reads child_home.dart for the word).
export 'access_settings.dart' show kChildTarget, kChildTargetLarger, kGuardianTarget, kGuardianTargetLarger;

// ================================================================= the scope ==
class AccessScope extends InheritedNotifier<AccessController> {
  const AccessScope({super.key, required AccessController controller, required super.child})
      : super(notifier: controller);

  /// The current settings, rebuilding the caller when they change. With no
  /// scope above, the defaults (the app as it was).
  static AccessSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccessScope>()?.notifier?.value ??
      AccessSettings.defaults;

  /// Her age as the host knows it, for the read-aloud default. Null if unknown.
  static int? ageOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccessScope>()?.notifier?.ageYears;
}

/// Installs the scope and applies the settings that have to be applied from
/// above: reduced motion (as MediaQuery.disableAnimations, so Flutter's own
/// widgets and ours agree) and roomier reading (as the theme's text styles).
/// Put it in MaterialApp.builder, inside any AnimatedTheme.
class AccessHost extends StatefulWidget {
  const AccessHost({super.key, required this.controller, required this.child, this.loadOnStart = true});
  final AccessController controller;
  final Widget child;

  /// Tests that preload the controller turn this off.
  final bool loadOnStart;

  @override
  State<AccessHost> createState() => _AccessHostState();
}

class _AccessHostState extends State<AccessHost> {
  @override
  void initState() {
    super.initState();
    if (widget.loadOnStart && !widget.controller.loaded) widget.controller.load();
  }

  @override
  Widget build(BuildContext context) => AccessScope(
        controller: widget.controller,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (BuildContext context, Widget? _) {
            final AccessSettings s = widget.controller.value;
            Widget out = widget.child;
            if (s.roomierReading) {
              final ThemeData t = Theme.of(context);
              out = Theme(data: t.copyWith(textTheme: roomierTextTheme(t.textTheme),
                  primaryTextTheme: roomierTextTheme(t.primaryTextTheme)), child: out);
            }
            if (s.largerTargets) {
              out = Theme(data: largerTargetsTheme(Theme.of(context), childTargetFor(s)), child: out);
            }
            if (s.reduceMotion) {
              final MediaQueryData mq = MediaQuery.of(context);
              out = MediaQuery(data: mq.copyWith(disableAnimations: true), child: out);
            }
            return out;
          },
        ),
      );
}

// ============================================================== reduce motion ==
/// True when the OS asks for no animation, or the guardian chose reduced motion
/// for her device.
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true || AccessScope.of(context).reduceMotion;

/// The duration for one consequence animation of [baseMs]. Zero when motion is
/// reduced: the result is simply there. Never longer than [maxConsequenceMs]
/// even when not reduced, so a screen cannot make her wait for a picture.
Duration motionDuration(BuildContext context, int baseMs) =>
    reduceMotionOf(context) ? Duration.zero : Duration(milliseconds: baseMs.clamp(0, maxConsequenceMs));

/// Milliseconds form of [motionDuration], for code that holds ints
/// (motion_rules.dart's durationFor takes and returns ints).
int motionMs(BuildContext context, int baseMs) => motionDuration(context, baseMs).inMilliseconds;

/// A transition builder that is always a plain fade: the "crossfade, never
/// travel" shape reduced motion collapses every switcher to.
Widget fadeOnlyTransition(Widget child, Animation<double> animation) =>
    FadeTransition(opacity: animation, child: child);

/// An AnimatedSwitcher for a consequence: a fade, timed by [motionDuration].
/// The one widget screens use instead of AnimatedSwitcher + a transition that
/// scales or slides.
class ConsequenceSwitcher extends StatelessWidget {
  const ConsequenceSwitcher({super.key, required this.child, this.ms = 220, this.alignment = Alignment.center});
  final Widget child;
  final int ms;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: motionDuration(context, ms),
        transitionBuilder: fadeOnlyTransition,
        layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
            alignment: alignment, children: <Widget>[...previous, ?current]),
        child: child,
      );
}

// ============================================================ roomier reading ==
/// Letter spacing, word spacing and line height for the "roomier reading"
/// option, from the British Dyslexia Association's published guidance (about
/// 0.12em letter spacing, 0.16em word spacing, 1.5 line height). Not a special
/// font: the evidence for dyslexia fonts is mixed, and the body face is already
/// Atkinson Hyperlegible (theme_data.dart). Applied through the theme's text
/// styles, so every screen inherits it with no per-screen edit.
const double roomyLetterSpacingEm = 0.12;
const double roomyWordSpacingEm = 0.16;
const double roomyLineHeight = 1.5;

TextStyle? roomierStyle(TextStyle? s) {
  if (s == null) return null;
  final double size = s.fontSize ?? 14;
  final double h = s.height ?? 1.0;
  return s.copyWith(
    letterSpacing: size * roomyLetterSpacingEm,
    wordSpacing: size * roomyWordSpacingEm,
    height: h < roomyLineHeight ? roomyLineHeight : h,
  );
}

TextTheme roomierTextTheme(TextTheme t) => t.copyWith(
      displayLarge: roomierStyle(t.displayLarge), displayMedium: roomierStyle(t.displayMedium),
      displaySmall: roomierStyle(t.displaySmall), headlineLarge: roomierStyle(t.headlineLarge),
      headlineMedium: roomierStyle(t.headlineMedium), headlineSmall: roomierStyle(t.headlineSmall),
      titleLarge: roomierStyle(t.titleLarge), titleMedium: roomierStyle(t.titleMedium),
      titleSmall: roomierStyle(t.titleSmall), bodyLarge: roomierStyle(t.bodyLarge),
      bodyMedium: roomierStyle(t.bodyMedium), bodySmall: roomierStyle(t.bodySmall),
      labelLarge: roomierStyle(t.labelLarge), labelMedium: roomierStyle(t.labelMedium),
      labelSmall: roomierStyle(t.labelSmall),
    );

/// A hand-set reading style, made roomier when the guardian chose it. Used where
/// a screen sets its own text size (story pages) and so would not otherwise
/// inherit the theme's roomier text styles.
TextStyle readingStyleOf(BuildContext context, TextStyle base) =>
    AccessScope.of(context).roomierReading ? roomierStyle(base)! : base;

/// Reading text is left-aligned under the roomier option; centred or justified
/// paragraphs are harder to track. Short headings keep their own alignment.
TextAlign readingAlign(BuildContext context, TextAlign declared) =>
    AccessScope.of(context).roomierReading &&
            (declared == TextAlign.center || declared == TextAlign.justify)
        ? TextAlign.start
        : declared;

// ============================================================== live regions ==
/// A line a screen reader announces when it changes: a turn change, "waiting for
/// …". P2-SAFE BY CONTRACT: what goes in is plain words about whose turn it is,
/// never a score, a count or a ranking (game_semantics_test.dart holds the
/// games' own lines to that).
class LiveLine extends StatelessWidget {
  const LiveLine({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(liveRegion: true, container: true, child: child);
}

// ================================================================== targets ==
/// [t] with every Material button raised to at least [floor] in both directions
/// (the "larger targets" option). A button inside a fixed-size box keeps that box:
/// this only lifts the minimum, it never makes anything overflow its parent.
ThemeData largerTargetsTheme(ThemeData t, double floor) {
  final WidgetStateProperty<Size> min = WidgetStatePropertyAll<Size>(Size(floor, floor));
  ButtonStyle lift(ButtonStyle? s) => (s ?? const ButtonStyle()).copyWith(minimumSize: min);
  return t.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: lift(t.filledButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: lift(t.elevatedButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: lift(t.outlinedButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: lift(t.textButtonTheme.style)),
    iconButtonTheme: IconButtonThemeData(style: lift(t.iconButtonTheme.style)),
  );
}

/// The floor for a child control right now (64, or 80 with larger targets).
double childTargetOf(BuildContext context) => childTargetFor(AccessScope.of(context));

/// The floor for a guardian control right now (48, or 64 with larger targets).
double guardianTargetOf(BuildContext context) => guardianTargetFor(AccessScope.of(context));
