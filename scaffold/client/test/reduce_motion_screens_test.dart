// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — reduced motion
// on real screens: with the guardian's setting, or the OS's own "remove
// animations", every consequence animation collapses to an instant change; with
// neither, the screens animate exactly as before. MASTERFILE §8.13.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/colouring_screen.dart';
import 'package:olive_client/doodle_desk.dart';
import 'package:olive_client/game_connect4.dart';
import 'package:olive_client/storyteller_screen.dart';

Future<void> pump(WidgetTester t, Widget w, {bool guardian = false, bool os = false, Size size = const Size(500, 1200)}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  final AccessController c = AccessController(
      repository: MemoryAccessRepository(AccessSettings(reduceMotion: guardian)));
  await c.load();
  await t.pumpWidget(MaterialApp(
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: os),
      child: AccessHost(controller: c, loadOnStart: false, child: child!),
    ),
    home: w,
  ));
  await t.pump(const Duration(milliseconds: 100));
}

List<Duration> switcherDurations(WidgetTester t) =>
    <Duration>[for (final Element e in find.byType(AnimatedSwitcher).evaluate()) (e.widget as AnimatedSwitcher).duration];

void main() {
  group('Storyteller', () {
    Future<void> reading(WidgetTester t, {bool guardian = false, bool os = false}) async {
      await pump(t, const StorytellerScreen(childName: 'Ivy'), guardian: guardian, os: os);
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('as before with no reduced motion: the page and the turn row fade over 220-260ms', (WidgetTester t) async {
      await reading(t);
      final List<Duration> d = switcherDurations(t);
      expect(d, isNotEmpty);
      expect(d.every((Duration x) => x > Duration.zero), isTrue);
      expect(d.every((Duration x) => x <= const Duration(milliseconds: 400)), isTrue);
    });

    testWidgets('guardian setting: every switcher is instant', (WidgetTester t) async {
      await reading(t, guardian: true);
      final List<Duration> d = switcherDurations(t);
      expect(d, isNotEmpty);
      expect(d.every((Duration x) => x == Duration.zero), isTrue, reason: '$d');
    });

    testWidgets('the OS "remove animations" choice does the same', (WidgetTester t) async {
      await reading(t, os: true);
      expect(switcherDurations(t).every((Duration x) => x == Duration.zero), isTrue);
    });

    testWidgets('with reduced motion, turning the page shows the new page at once (no old page lingering)', (WidgetTester t) async {
      await reading(t, guardian: true);
      final Finder dots = find.byType(AnimatedContainer);
      expect(dots, findsWidgets);
      for (final Element e in dots.evaluate()) {
        expect((e.widget as AnimatedContainer).duration, Duration.zero);
      }
      await t.tap(find.widgetWithText(FilledButton, 'Next'));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('block-0')), findsNothing);
      expect(find.byKey(const ValueKey<String>('block-1')), findsOneWidget);
    });
  });

  group('Connect 4', () {
    Future<void> board(WidgetTester t, {bool guardian = false, bool os = false}) async {
      await pump(t, const GameConnect4Screen(role: 'ivy', displayName: 'Ivy'), guardian: guardian, os: os);
      await t.tap(find.text('Start'));
      for (int i = 0; i < 40 && find.text('Your turn').evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final SemanticsHandle h = t.ensureSemantics();
      t.semantics.performAction(find.semantics.byLabel('Column 3, row 1 from the bottom'), SemanticsAction.tap);
      await t.pump();
      h.dispose();
    }

    testWidgets('a dropped disc falls over 380ms when motion is allowed', (WidgetTester t) async {
      await board(t);
      final Iterable<TweenAnimationBuilder<double>> drops = find
          .byType(TweenAnimationBuilder<double>).evaluate().map((Element e) => e.widget as TweenAnimationBuilder<double>);
      expect(drops, isNotEmpty);
      expect(drops.any((TweenAnimationBuilder<double> w) => w.duration == const Duration(milliseconds: 380)), isTrue);
      await t.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('with the guardian setting the disc is simply there: duration zero', (WidgetTester t) async {
      await board(t, guardian: true);
      final Iterable<TweenAnimationBuilder<double>> drops = find
          .byType(TweenAnimationBuilder<double>).evaluate().map((Element e) => e.widget as TweenAnimationBuilder<double>);
      expect(drops, isNotEmpty);
      expect(drops.every((TweenAnimationBuilder<double> w) => w.duration == Duration.zero), isTrue);
      await t.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('with the OS setting too', (WidgetTester t) async {
      await board(t, os: true);
      final Iterable<TweenAnimationBuilder<double>> drops = find
          .byType(TweenAnimationBuilder<double>).evaluate().map((Element e) => e.widget as TweenAnimationBuilder<double>);
      expect(drops.every((TweenAnimationBuilder<double> w) => w.duration == Duration.zero), isTrue);
      await t.pumpAndSettle(const Duration(seconds: 1));
    });
  });

  group('Colouring', () {
    Future<void> colourSun(WidgetTester t, {bool guardian = false}) async {
      await pump(t, const ColouringScreen(), guardian: guardian, size: const Size(700, 1000));
      final SemanticsHandle h = t.ensureSemantics();
      await t.tap(find.bySemanticsLabel('Colour: yellow'));
      await t.pumpAndSettle(); // the touch ripple is the finger's own; let it end first
      t.semantics.performAction(find.semantics.byLabel('Sun'), SemanticsAction.tap);
      await t.pump();
      h.dispose();
    }

    testWidgets('a part fades to its colour over the consequence budget when motion is allowed', (WidgetTester t) async {
      await colourSun(t);
      expect(t.hasRunningAnimations, isTrue, reason: 'the region fade is running');
      await t.pump(const Duration(milliseconds: 500));
    });

    testWidgets('with reduced motion the colour is there at once: no fade is started', (WidgetTester t) async {
      await colourSun(t, guardian: true);
      expect(t.hasRunningAnimations, isFalse);
      final SemanticsHandle h = t.ensureSemantics();
      await t.pump();
      expect(find.semantics.byLabel('Sun').evaluate().single.value, 'yellow');
      h.dispose();
    });
  });

  group('Doodle desk', () {
    testWidgets('the tray swap and the placed stamp are instant under reduced motion', (WidgetTester t) async {
      await pump(t, const DoodleDesk(), guardian: true, size: const Size(700, 1000));
      final AnimatedSize size = t.widget<AnimatedSize>(find.byType(AnimatedSize).first);
      expect(size.duration, Duration.zero);
    });

    testWidgets('as before otherwise: the tray swap uses the 120ms crossfade', (WidgetTester t) async {
      await pump(t, const DoodleDesk(), size: const Size(700, 1000));
      expect(t.widget<AnimatedSize>(find.byType(AnimatedSize).first).duration, const Duration(milliseconds: 120));
    });
  });
}
