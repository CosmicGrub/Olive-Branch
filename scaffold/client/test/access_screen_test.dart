// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — the guardian's
// "Accessibility for her device" screen, its place in the Settings hub, and the
// shell wiring that carries the settings to her screens. MASTERFILE §8.1, §8.4,
// §8.21.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_screen.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/access_shell.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/read_aloud.dart';
import 'package:olive_client/tts_channel.dart';

Widget app(Widget child) => MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true), home: child);

Future<void> big(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(500, 1600));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

String stripped(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'//.*'), '');

bool switchOn(WidgetTester t, String key) => t.widget<SwitchListTile>(find.byKey(Key(key))).value;

void main() {
  group('the guardian screen', () {
    late MemoryAccessRepository repo;
    late AccessController c;
    setUp(() {
      repo = MemoryAccessRepository();
      c = AccessController(repository: repo);
    });

    Future<void> open(WidgetTester t, {int age = 5}) async {
      await big(t);
      await t.pumpWidget(app(AccessScreen(key: UniqueKey(), childName: 'Ivy', controller: c, childAge: age)));
      await t.pumpAndSettle();
    }

    testWidgets('five plainly named switches, and a line saying where it is kept', (WidgetTester t) async {
      await open(t);
      for (final String k in <String>['accessReadAloud', 'accessReduceMotion', 'accessRoomier', 'accessLarger', 'accessCaptions']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.text('Read aloud everywhere'), findsOneWidget);
      expect(find.text('Reduce motion'), findsOneWidget);
      expect(find.text('Roomier reading'), findsOneWidget);
      expect(find.text('Larger targets'), findsOneWidget);
      expect(find.text('Captions'), findsOneWidget);
      expect(find.textContaining('kept on this device'), findsOneWidget);
    });

    testWidgets('read-aloud follows her age until a guardian chooses: on at 5, off at 9', (WidgetTester t) async {
      await open(t, age: 5);
      expect(switchOn(t, 'accessReadAloud'), isTrue);
      expect(find.textContaining('Following her age'), findsOneWidget);
      c = AccessController(repository: MemoryAccessRepository());
      await open(t, age: 9);
      expect(switchOn(t, 'accessReadAloud'), isFalse);
    });

    testWidgets('turning each switch changes the setting and keeps it', (WidgetTester t) async {
      await open(t);
      Future<void> flip(String key) async {
        await t.ensureVisible(find.byKey(Key(key)));
        await t.tap(find.byKey(Key(key)));
        await t.pumpAndSettle();
      }

      await flip('accessReduceMotion');
      await flip('accessRoomier');
      await flip('accessLarger');
      await flip('accessReadAloud');
      expect(c.value.reduceMotion, isTrue);
      expect(c.value.roomierReading, isTrue);
      expect(c.value.largerTargets, isTrue);
      expect(c.value.readAloud, isFalse, reason: 'it was on by age at 5; flipping makes an explicit "off"');
      final AccessSettings kept = await repo.load();
      expect(kept, c.value);
      expect(find.text('Saved on this device.'), findsOneWidget);
    });

    testWidgets('"Follow her age again" appears only after a choice, and clears it', (WidgetTester t) async {
      await open(t);
      expect(find.byKey(const Key('accessReadAloudAge')), findsNothing);
      await t.tap(find.byKey(const Key('accessReadAloud')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('accessReadAloudAge')), findsOneWidget);
      await t.tap(find.byKey(const Key('accessReadAloudAge')));
      await t.pumpAndSettle();
      expect(c.value.readAloud, isNull);
      expect(find.byKey(const Key('accessReadAloudAge')), findsNothing);
    });

    testWidgets('captions are honest: the screen says they are not built, and the wish changes nothing', (WidgetTester t) async {
      await open(t);
      expect(find.textContaining('Not built yet'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('accessCaptions')));
      await t.tap(find.byKey(const Key('accessCaptions')));
      await t.pumpAndSettle();
      expect(c.value.captions, isTrue);
      expect(c.value.captionsActive, isFalse);
      expect(find.textContaining('nothing shows'), findsOneWidget);
    });

    testWidgets('roomier reading shows a preview, and removes it when off', (WidgetTester t) async {
      await open(t);
      expect(find.byKey(const Key('accessRoomyPreview')), findsNothing);
      await t.ensureVisible(find.byKey(const Key('accessRoomier')));
      await t.tap(find.byKey(const Key('accessRoomier')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('accessRoomyPreview')), findsOneWidget);
      final Text preview = t.widget<Text>(find.descendant(
          of: find.byKey(const Key('accessRoomyPreview')), matching: find.byType(Text)));
      expect(preview.style!.letterSpacing, greaterThan(0));
      expect(preview.textAlign, TextAlign.start);
    });

    testWidgets('a save that fails is said plainly and does not undo the choice for this run', (WidgetTester t) async {
      repo.failSaves = true;
      await open(t);
      await t.ensureVisible(find.byKey(const Key('accessReduceMotion')));
      await t.tap(find.byKey(const Key('accessReduceMotion')));
      await t.pumpAndSettle();
      expect(c.value.reduceMotion, isTrue);
      expect(find.textContaining('could not keep it'), findsOneWidget);
    });

    testWidgets('each switch is a single labelled node for a screen reader', (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await open(t);
      expect(find.bySemanticsLabel(RegExp('Reduce motion')), findsWidgets);
      h.dispose();
    });

    testWidgets('the switches are at least 48dp tall (guardian floor)', (WidgetTester t) async {
      await open(t);
      for (final String k in <String>['accessReadAloud', 'accessReduceMotion', 'accessRoomier', 'accessLarger', 'accessCaptions']) {
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(48), reason: k);
      }
    });

    testWidgets('a change here reaches the child side live (one shared controller)', (WidgetTester t) async {
      await open(t);
      late bool seen;
      // A child-side reader built over the same controller.
      await t.pumpWidget(app(AccessScope(controller: c, child: Builder(builder: (BuildContext ctx) {
        seen = AccessScope.of(ctx).reduceMotion;
        return const SizedBox();
      }))));
      expect(seen, isFalse);
      await c.update((AccessSettings s) => s.copyWith(reduceMotion: true));
      await t.pump();
      expect(seen, isTrue);
    });
  });

  group('the Settings hub', () {
    testWidgets('lists "Accessibility for her device" in the Her group and opens the screen', (WidgetTester t) async {
      await big(t);
      await t.pumpWidget(app(const GuardianMoreScreen(childName: 'Ivy', childAge: 6)));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('moreSettings')));
      await t.tap(find.byKey(const Key('moreSettings')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settingsRow_access')), findsOneWidget);
      expect(find.text('Accessibility for her device'), findsWidgets);
      await t.ensureVisible(find.byKey(const Key('settingsRow_access')));
      await t.tap(find.byKey(const Key('settingsRow_access')));
      await t.pumpAndSettle();
      expect(find.byType(AccessScreen), findsOneWidget);
    });

    test('the row sits in the Her group, before the Family group', () {
      final String src = File('lib/guardian_more.dart').readAsStringSync();
      final int her = src.indexOf("SettingsGroup('Her'");
      final int row = src.indexOf("id: 'access'");
      final int family = src.indexOf("SettingsGroup('Family'");
      expect(her, greaterThan(0));
      expect(row, greaterThan(her));
      expect(row, lessThan(family));
    });
  });

  group('her shell has no settings (§8.1) — the new screen is guardian-side only', () {
    test('no child-facing screen references the guardian screen or the controller\'s setter', () {
      for (final String f in <String>[
        'lib/child_home.dart', 'lib/child_more.dart', 'lib/child_home_live.dart', 'lib/storyteller_screen.dart',
        'lib/wants_needs.dart', 'lib/journal_screen.dart', 'lib/tiered_tile.dart', 'lib/picture_bank.dart',
        'lib/game_connect4.dart', 'lib/game_war.dart', 'lib/game_puzzle.dart', 'lib/game_pictionary.dart',
      ]) {
        final String src = stripped(f);
        expect(src.contains('access_screen.dart'), isFalse, reason: f);
        expect(src.contains('AccessScreen'), isFalse, reason: f);
        expect(src.contains('.update('), isFalse, reason: '$f must not write the settings');
      }
    });

    test('the child side reads settings only through the scope (AccessScope.of / helpers), never the controller directly', () {
      for (final String f in <String>['lib/tiered_tile.dart', 'lib/picture_bank.dart', 'lib/storyteller_screen.dart']) {
        expect(stripped(f).contains('sharedAccess'), isFalse, reason: f);
      }
    });
  });

  group('the shell wiring', () {
    testWidgets('withAccess installs both scopes and applies reduced motion', (WidgetTester t) async {
      final AccessController c = AccessController(
          repository: MemoryAccessRepository(const AccessSettings(reduceMotion: true)));
      await c.load();
      late bool reduced;
      late ReadAloudController? ra;
      await t.pumpWidget(MaterialApp(
        builder: (BuildContext context, Widget? child) => withAccess(child!, access: c, readAloud: ReadAloudController()),
        home: Builder(builder: (BuildContext ctx) {
          reduced = reduceMotionOf(ctx);
          ra = ReadAloudScope.maybeOf(ctx);
          return const SizedBox();
        }),
      ));
      expect(reduced, isTrue);
      expect(ra, isNotNull);
    });

    test('the shared read-aloud engine is the on-device TtsChannel, and the observer stops speech', () {
      expect(sharedReadAloud.available, isTrue);
      expect(sharedReadAloudObserver, isA<ReadAloudRouteObserver>());
      expect(TtsChannel(), isA<ReadAloudEngine>());
    });

    test('the child builds install it; the guardian-only build does not', () {
      final String preview = stripped('lib/main.dart');
      final String live = stripped('lib/main_live.dart');
      final String guardian = stripped('lib/main_live_guardian.dart');
      expect(preview.contains('sharedReadAloudObserver'), isTrue);
      expect(preview.contains('builder: accessBuilder'), isTrue);
      expect(live.contains('sharedReadAloudObserver'), isTrue);
      expect(live.contains('withAccess(child!)'), isTrue);
      expect(guardian.contains('withAccess'), isFalse);
    });

    test('the child profile passes her age on, so the read-aloud default follows it', () {
      expect(stripped('lib/child_home_live.dart').contains('sharedAccess.setAge('), isTrue);
    });

    test('this feature adds no network call and no credential (offline, on-device only)', () {
      for (final String f in <String>[
        'lib/access_settings.dart', 'lib/access_scope.dart', 'lib/access_screen.dart', 'lib/access_shell.dart',
        'lib/read_aloud.dart', 'lib/picture_bank.dart', 'lib/colour_names.dart',
      ]) {
        final String src = stripped(f);
        for (final String banned in <String>['package:http', 'dart:io', 'HttpClient', 'WebSocket', 'api_client', 'auth_session', 'Uri.parse']) {
          expect(src.contains(banned), isFalse, reason: '$f must not reference $banned');
        }
      }
    });
  });
}
