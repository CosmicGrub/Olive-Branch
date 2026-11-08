// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — the
// accessibility scope: reduced motion (one helper, OS and guardian), roomier
// reading, larger targets, live regions. MASTERFILE §8.4, §8.13, §8.19.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/motion_rules.dart';

Future<AccessController> loaded(AccessSettings s, {int? age}) async {
  final AccessController c = AccessController(repository: MemoryAccessRepository(s), ageYears: age);
  await c.load();
  return c;
}

Widget app(AccessController c, Widget child, {bool osReduce = false}) => MaterialApp(
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
      builder: (BuildContext context, Widget? w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: osReduce),
        child: AccessHost(controller: c, loadOnStart: false, child: w!),
      ),
      home: Scaffold(body: child),
    );

void main() {
  group('reduce motion — one helper', () {
    testWidgets('off: a consequence keeps its duration (capped at the 400ms budget)', (WidgetTester t) async {
      late Duration d200, d900;
      await t.pumpWidget(app(await loaded(AccessSettings.defaults), Builder(builder: (BuildContext c) {
        d200 = motionDuration(c, 200);
        d900 = motionDuration(c, 900);
        return const SizedBox();
      })));
      expect(d200, const Duration(milliseconds: 200));
      expect(d900, const Duration(milliseconds: maxConsequenceMs), reason: 'never longer than §8.13.1 allows');
    });

    testWidgets('the guardian setting collapses every duration to zero', (WidgetTester t) async {
      late Duration d;
      late bool reduced;
      await t.pumpWidget(app(await loaded(const AccessSettings(reduceMotion: true)), Builder(builder: (BuildContext c) {
        d = motionDuration(c, 300);
        reduced = reduceMotionOf(c);
        return const SizedBox();
      })));
      expect(reduced, isTrue);
      expect(d, Duration.zero);
    });

    testWidgets('the OS "remove animations" choice does the same, with no guardian setting', (WidgetTester t) async {
      late Duration d;
      await t.pumpWidget(app(await loaded(AccessSettings.defaults), Builder(builder: (BuildContext c) {
        d = motionDuration(c, 300);
        return const SizedBox();
      }), osReduce: true));
      expect(d, Duration.zero);
    });

    testWidgets('the host publishes the guardian choice as MediaQuery.disableAnimations, so Flutter\'s own widgets agree',
        (WidgetTester t) async {
      late bool flag;
      await t.pumpWidget(app(await loaded(const AccessSettings(reduceMotion: true)), Builder(builder: (BuildContext c) {
        flag = MediaQuery.disableAnimationsOf(c);
        return const SizedBox();
      })));
      expect(flag, isTrue);
    });

    testWidgets('with no scope at all (every existing screen) motion is as it always was', (WidgetTester t) async {
      late Duration d;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) {
        d = motionDuration(c, 250);
        return const SizedBox();
      })));
      expect(d, const Duration(milliseconds: 250));
    });

    testWidgets('changing the setting takes effect live, without rebuilding the app', (WidgetTester t) async {
      final AccessController c = await loaded(AccessSettings.defaults);
      late Duration d;
      await t.pumpWidget(app(c, Builder(builder: (BuildContext ctx) {
        d = motionDuration(ctx, 300);
        return const SizedBox();
      })));
      expect(d, const Duration(milliseconds: 300));
      await c.update((AccessSettings s) => s.copyWith(reduceMotion: true));
      await t.pump();
      expect(d, Duration.zero);
    });

    testWidgets('ConsequenceSwitcher is a fade only, instant when reduced', (WidgetTester t) async {
      final AccessController c = await loaded(const AccessSettings(reduceMotion: true));
      await t.pumpWidget(app(c, const ConsequenceSwitcher(child: Text('one', key: ValueKey('a')))));
      await t.pumpWidget(app(c, const ConsequenceSwitcher(child: Text('two', key: ValueKey('b')))));
      expect(t.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration, Duration.zero);
      await t.pump();
      expect(find.text('one'), findsNothing, reason: 'the old child is gone at once: no travel, no overlap');
      expect(find.text('two'), findsOneWidget);
    });

    testWidgets('ConsequenceSwitcher uses a FadeTransition, never a scale or slide', (WidgetTester t) async {
      final AccessController c = await loaded(AccessSettings.defaults);
      await t.pumpWidget(app(c, const ConsequenceSwitcher(child: Text('one', key: ValueKey('a')))));
      await t.pumpWidget(app(c, const ConsequenceSwitcher(child: Text('two', key: ValueKey('b')))));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.descendant(of: find.byType(AnimatedSwitcher), matching: find.byType(FadeTransition)),
          findsWidgets);
      expect(find.descendant(of: find.byType(AnimatedSwitcher), matching: find.byType(ScaleTransition)), findsNothing);
      expect(find.descendant(of: find.byType(AnimatedSwitcher), matching: find.byType(SlideTransition)), findsNothing);
      await t.pumpAndSettle();
    });

    test('NO consequence animation in the app keeps its own raw duration (source guard)', () {
      // Every implicit animation takes its duration from motionDuration(); a raw
      // `duration: const Duration(milliseconds: …)` would not obey reduced motion.
      // Allowed: motion_rules.dart (the budget itself), main_live.dart's guardian-
      // initiated theme crossfade, call_screen.dart (calls are parked and untouched),
      // and the two controllers that read the setting in didChangeDependencies.
      const Set<String> allowed = <String>{
        'main_live.dart', 'main_live_guardian.dart', 'main_live_child_call_test.dart',
        'main_live_child_kiosk_call_test.dart', 'main_live_dad_answer_test.dart',
        'main_live_guardian_call_test.dart', 'call_screen.dart',
        'birthday_marked.dart', 'game_uno.dart', 'access_scope.dart',
      };
      final RegExp raw = RegExp(r'duration:\s*(const\s+)?Duration\(\s*milliseconds:');
      final List<String> offenders = <String>[];
      for (final FileSystemEntity f in Directory('lib').listSync()) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String name = f.uri.pathSegments.last;
        if (allowed.contains(name)) continue;
        final String src = f.readAsStringSync().replaceAll(RegExp(r'//.*'), '');
        if (raw.hasMatch(src)) offenders.add(name);
      }
      expect(offenders, isEmpty, reason: 'these files animate with a raw duration: $offenders');
    });

    test('the two controllers that cannot use a context in initState read the setting once it is available', () {
      final String uno = File('lib/game_uno.dart').readAsStringSync();
      final String birthday = File('lib/birthday_marked.dart').readAsStringSync();
      expect(uno.contains('_controller.duration = motionDuration(context, 400)'), isTrue);
      expect(birthday.contains('_pop.duration = motionDuration(context, 300)'), isTrue);
    });

    test('no new autonomous motion: the helper starts nothing and a still surface stays still', () {
      expect(autonomousIsNeverAllowed, isTrue);
      expect(quietnessOf('journal'), Quietness.still);
      expect(quietnessOf('homework'), Quietness.still);
      expect(effectiveQuietness('journal', true), Quietness.still);
      expect(effectiveQuietness('doodle', true), Quietness.reduced);
      final String src = File('lib/access_scope.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      expect(src.contains('Timer'), isFalse);
      expect(src.contains('AnimationController'), isFalse);
      expect(src.contains('repeat('), isFalse);
    });
  });

  group('roomier reading', () {
    test('adds letter spacing, word spacing and a 1.5 line height; never shrinks an already roomier line', () {
      final TextStyle s = roomierStyle(const TextStyle(fontSize: 20, height: 1.1))!;
      expect(s.letterSpacing, closeTo(20 * 0.12, 1e-9));
      expect(s.wordSpacing, closeTo(20 * 0.16, 1e-9));
      expect(s.height, 1.5);
      expect(roomierStyle(const TextStyle(fontSize: 14, height: 1.8))!.height, 1.8);
      expect(roomierStyle(null), isNull);
    });

    test('applies to every text-theme role', () {
      final TextTheme t = roomierTextTheme(ThemeData(useMaterial3: true).textTheme);
      for (final TextStyle? s in <TextStyle?>[
        t.displayLarge, t.displayMedium, t.displaySmall, t.headlineLarge, t.headlineMedium,
        t.headlineSmall, t.titleLarge, t.titleMedium, t.titleSmall, t.bodyLarge, t.bodyMedium,
        t.bodySmall, t.labelLarge, t.labelMedium, t.labelSmall,
      ]) {
        expect(s!.letterSpacing, greaterThan(0));
        expect(s.height, greaterThanOrEqualTo(1.5));
      }
    });

    test('is not a special font: the family is untouched', () {
      final TextTheme base = ThemeData(useMaterial3: true, fontFamily: 'AtkinsonHyperlegible').textTheme;
      expect(roomierTextTheme(base).bodyLarge!.fontFamily, base.bodyLarge!.fontFamily);
    });

    testWidgets('the host applies it through the theme, so a screen inherits it with no edit', (WidgetTester t) async {
      late TextStyle? body;
      await t.pumpWidget(app(await loaded(const AccessSettings(roomierReading: true)), Builder(builder: (BuildContext c) {
        body = Theme.of(c).textTheme.bodyMedium;
        return const SizedBox();
      })));
      expect(body!.letterSpacing, greaterThan(0));
      expect(body!.height, greaterThanOrEqualTo(1.5));
    });

    testWidgets('off: the theme is untouched', (WidgetTester t) async {
      late TextStyle? body;
      await t.pumpWidget(app(await loaded(AccessSettings.defaults), Builder(builder: (BuildContext c) {
        body = Theme.of(c).textTheme.bodyMedium;
        return const SizedBox();
      })));
      TextStyle? plain;
      await t.pumpWidget(MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
          home: Builder(builder: (BuildContext c) {
            plain = Theme.of(c).textTheme.bodyMedium;
            return const SizedBox();
          })));
      expect(body!.letterSpacing, plain!.letterSpacing);
      expect(body!.height, plain!.height);
    });

    testWidgets('reading text is left-aligned under the option, never centred or justified', (WidgetTester t) async {
      late TextAlign centred, justified, start;
      await t.pumpWidget(app(await loaded(const AccessSettings(roomierReading: true)), Builder(builder: (BuildContext c) {
        centred = readingAlign(c, TextAlign.center);
        justified = readingAlign(c, TextAlign.justify);
        start = readingAlign(c, TextAlign.start);
        return const SizedBox();
      })));
      expect(centred, TextAlign.start);
      expect(justified, TextAlign.start);
      expect(start, TextAlign.start);
    });

    testWidgets('off: alignment is exactly what the screen declared', (WidgetTester t) async {
      late TextAlign centred;
      await t.pumpWidget(app(await loaded(AccessSettings.defaults), Builder(builder: (BuildContext c) {
        centred = readingAlign(c, TextAlign.center);
        return const SizedBox();
      })));
      expect(centred, TextAlign.center);
    });
  });

  group('larger targets', () {
    testWidgets('lifts every Material button minimum to 80dp, and leaves them alone when off', (WidgetTester t) async {
      Future<Size> size(AccessSettings s) async {
        await t.pumpWidget(app(await loaded(s), const Center(child: FilledButton(onPressed: null, child: Text('x')))));
        return t.getSize(find.byType(FilledButton));
      }

      final Size off = await size(AccessSettings.defaults);
      final Size on = await size(const AccessSettings(largerTargets: true));
      expect(off.height, lessThan(80));
      expect(on.height, greaterThanOrEqualTo(80));
      expect(on.width, greaterThanOrEqualTo(80));
    });

    testWidgets('icon buttons are lifted too', (WidgetTester t) async {
      await t.pumpWidget(app(await loaded(const AccessSettings(largerTargets: true)),
          Center(child: IconButton(onPressed: () {}, icon: const Icon(Icons.star)))));
      expect(t.getSize(find.byType(IconButton)).height, greaterThanOrEqualTo(80));
    });

    testWidgets('childTargetOf and guardianTargetOf follow the setting', (WidgetTester t) async {
      late double child, guardian;
      await t.pumpWidget(app(await loaded(const AccessSettings(largerTargets: true)), Builder(builder: (BuildContext c) {
        child = childTargetOf(c);
        guardian = guardianTargetOf(c);
        return const SizedBox();
      })));
      expect(child, 80);
      expect(guardian, 64);
    });
  });

  group('live regions', () {
    testWidgets('LiveLine is a live region carrying its text', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await t.pumpWidget(app(await loaded(AccessSettings.defaults), const LiveLine(child: Text('Your turn'))));
      final SemanticsNode n = t.getSemantics(find.text('Your turn'));
      expect(n.flagsCollection.isLiveRegion, isTrue);
      expect(n.label, 'Your turn');
      h.dispose();
    });
  });
}
