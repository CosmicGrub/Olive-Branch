// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — read-aloud on
// the child's "More" rows and the game cards, and its absence on every
// grown-up screen that shares the same widgets. MASTERFILE §8.8.5, §8.21.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/hub_widgets.dart';
import 'package:olive_client/read_aloud.dart';

class _Engine implements ReadAloudEngine {
  final List<String> spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

Future<void> pump(WidgetTester t, Widget w, ReadAloudController ra, {AccessSettings s = AccessSettings.defaults}) async {
  await t.binding.setSurfaceSize(const Size(500, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final AccessController c = AccessController(repository: MemoryAccessRepository(s));
  await c.load();
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
    home: AccessScope(controller: c, child: ReadAloudScope(controller: ra, child: w)),
  ));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  group('the child\'s More rows', () {
    testWidgets('every row has its own speaker', (WidgetTester t) async {
      await pump(t, const ChildMoreScreen(childName: 'Ivy', childAge: 9), ReadAloudController(engine: _Engine()));
      final int rows = find.byType(HubTile).evaluate().length;
      expect(rows, greaterThanOrEqualTo(5));
      expect(find.descendant(of: find.byType(HubTile), matching: find.byKey(const Key('speakerButton'))),
          findsNWidgets(rows));
    });

    testWidgets('long-press reads a row\'s title and does not open it; a plain tap opens and does not read',
        (WidgetTester t) async {
      final _Engine e = _Engine();
      await pump(t, const ChildMoreScreen(childName: 'Ivy', childAge: 9), ReadAloudController(engine: e));
      final Finder first = find.byType(HubTile).first;
      final String title = t.widget<HubTile>(first).title;
      await t.longPress(first);
      await t.pump();
      expect(e.spoken, <String>[title]);
      expect(find.byType(ChildMoreScreen), findsOneWidget);
    });

    testWidgets('off when the guardian turns read-aloud off: no speakers on the rows', (WidgetTester t) async {
      await pump(t, const ChildMoreScreen(childName: 'Ivy', childAge: 9), ReadAloudController(engine: _Engine()),
          s: const AccessSettings(readAloud: false));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });

    testWidgets('with no scope the rows are exactly as before', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const MaterialApp(home: ChildMoreScreen(childName: 'Ivy', childAge: 9)));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });
  });

  group('grown-up screens sharing these widgets never get speakers', () {
    testWidgets('the guardian More hub, even with a read-aloud scope above it', (WidgetTester t) async {
      await pump(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 9), ReadAloudController(engine: _Engine()));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });

    testWidgets('the guardian home tiles', (WidgetTester t) async {
      await pump(
          t,
          const GuardianHome(
              childName: 'Ivy', childLocalTime: '9:14 PM', childZoneAbbr: 'EST', actorLocalTime: '6:14 PM',
              childStateSentence: 'Winding down', childBands: <RibbonBand>[], actorBands: <RibbonBand>[],
              overlapLabel: 'x'),
          ReadAloudController(engine: _Engine()));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });
  });

  group('game cards', () {
    testWidgets('a child\'s card has a speaker and reads the game\'s name on long-press', (WidgetTester t) async {
      final _Engine e = _Engine();
      await pump(t, const GamePickerScreen(childName: 'Ivy', childAge: 9), ReadAloudController(engine: e));
      expect(find.byKey(const Key('speakerButton')), findsWidgets);
      final Finder card = find.byWidgetPredicate((Widget w) => w.runtimeType.toString() == '_GameCard').first;
      await t.longPress(card);
      await t.pump();
      expect(e.spoken, hasLength(1));
      expect(e.spoken.single.trim(), isNotEmpty);
    });

    testWidgets('a guardian\'s card (the one with the favourite star) has no speaker', (WidgetTester t) async {
      await pump(
          t,
          GamePickerScreen(childName: 'Ivy', childAge: 9, onToggleFavorite: (String k, bool v) {},
              favoriteKinds: const <String>{}),
          ReadAloudController(engine: _Engine()));
      expect(find.byKey(const Key('speakerButton')), findsNothing);
    });
  });
}
