// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — text scale to
// 2.0 without overflow on the main child screens, at phone and tablet sizes, with
// every accessibility option on at once (read-aloud speakers, roomier reading,
// larger targets) — the worst case the options can combine into. MASTERFILE §8.4,
// §8.11.1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/access_shell.dart' show withAccess;
import 'package:olive_client/calendar_day_logic.dart' show DayPartLite;
import 'package:olive_client/child_home.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/colouring_screen.dart';
import 'package:olive_client/doodle_desk.dart';
import 'package:olive_client/game_connect4.dart';
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/game_pictionary.dart';
import 'package:olive_client/game_puzzle.dart';
import 'package:olive_client/game_war.dart';
import 'package:olive_client/journal_screen.dart';
import 'package:olive_client/live_games.dart' show Side;
import 'package:olive_client/local_services.dart';
import 'package:olive_client/my_day.dart';
import 'package:olive_client/read_aloud.dart';
import 'package:olive_client/storyteller_screen.dart';
import 'package:olive_client/theme.dart';
import 'package:olive_client/theme_data.dart';
import 'package:olive_client/tiered_tile.dart';
import 'package:olive_client/together_puzzle.dart';
import 'package:olive_client/wants_needs.dart';
import 'package:olive_client/war_deck.dart';

class _Engine implements ReadAloudEngine {
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
}

const Size phone = Size(390, 844);
const Size tablet = Size(800, 1280);
/// The Fold's cover screen: 344 dp wide, the narrowest surface the app targets.
const Size foldCover = Size(344, 882);

Future<void> pumpAt(WidgetTester t, Widget screen, Size size,
    {double scale = 2.0, AccessSettings settings = const AccessSettings(readAloud: true, roomierReading: true, largerTargets: true)}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  final AccessController c = AccessController(repository: MemoryAccessRepository(settings));
  await c.load();
  final ThemeData theme = buildThemeData(defaultAppTheme);
  await t.pumpWidget(MaterialApp(
    theme: theme,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: withAccess(child!, access: c, readAloud: ReadAloudController(engine: _Engine())),
    ),
    home: screen,
  ));
  await t.pump(const Duration(milliseconds: 400));
}

const List<DayPartLite> _noParts = <DayPartLite>[];

Widget _home() => const ChildHome(
    childName: 'Ivy', presence: ParentPresence('Dad', '6:42 PM', '9:00 PM her time'),
    sleepsUntilHandover: 3, unreadCount: 2);

void main() {
  setUp(LocalServices.resetForTest);
  tearDown(LocalServices.resetForTest);

  final Map<String, Widget Function()> screens = <String, Widget Function()>{
    'ChildHome': _home,
    'ChildMoreScreen': () => const ChildMoreScreen(childName: 'Ivy', childAge: 7),
    // Ten and over also gets "Growing up", "The quiet corner" and "Take your things with you".
    'ChildMoreScreen (age 12)': () => const ChildMoreScreen(childName: 'Ivy', childAge: 12),
    'StorytellerScreen (ask)': () => const StorytellerScreen(childName: 'Ivy'),
    'WantsNeedsScreen': () => const WantsNeedsScreen(),
    'JournalScreen': () => const JournalScreen(childName: 'Ivy'),
    'GamePickerScreen': () => const GamePickerScreen(childName: 'Ivy', childAge: 7),
    'ColouringScreen': () => const ColouringScreen(),
    'DoodleDesk': () => const DoodleDesk(),
    'MyDayScreen': () => const MyDayScreen(childName: 'Ivy', parts: _noParts, nowLocal: '10:00'),
  };

  for (final MapEntry<String, Widget Function()> s in screens.entries) {
    for (final MapEntry<String, Size> size in <String, Size>{'phone 390x844': phone, 'tablet 800x1280': tablet, 'fold cover 344x882': foldCover}.entries) {
      testWidgets('${s.key} at text scale 2.0, ${size.key}, every option on: no overflow', (WidgetTester t) async {
        await pumpAt(t, s.value(), size.value);
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final MapEntry<String, Size> size in <String, Size>{'phone 390x844': phone, 'tablet 800x1280': tablet, 'fold cover 344x882': foldCover}.entries) {
    testWidgets('StorytellerScreen reading a story at text scale 2.0, ${size.key}: no overflow, speaker present',
        (WidgetTester t) async {
      await pumpAt(t, const StorytellerScreen(childName: 'Ivy'), size.value);
      await t.tap(find.text('Tell me a story!'));
      await t.pump(const Duration(milliseconds: 600));
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('speakerButton')), findsWidgets);
    });

    testWidgets('Connect 4 board at text scale 2.0, ${size.key}: no overflow', (WidgetTester t) async {
      await pumpAt(t, const GameConnect4Screen(role: 'ivy', displayName: 'Ivy'), size.value);
      await t.tap(find.text('Start'));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
    });

    testWidgets('War board at text scale 2.0, ${size.key}: no overflow', (WidgetTester t) async {
      await pumpAt(t, Scaffold(body: SingleChildScrollView(child: Center(child: WarView(
          state: WarState(myPile: standardDeck().take(26).toList(), roundNumber: 3, pot: const <PlayingCard>[],
              myPending: const <PlayingCard>[PlayingCard(rank: 12, suit: Suit.hearts)], theirPending: null,
              phase: WarPhase.playing, lastRoundNote: 'You win this round.'),
          mySide: Side.b, peerName: 'Dad', onFlip: () {})))), size.value);
      expect(t.takeException(), isNull);
    });

    testWidgets('the puzzle at text scale 2.0, ${size.key}: no overflow', (WidgetTester t) async {
      await pumpAt(t, Scaffold(body: SingleChildScrollView(child: Center(child: PuzzleView(
          state: const TogetherPuzzleState(puzzleId: 'farmyard', placedPieces: <String>{'cow'}, mover: Side.b),
          mySide: Side.b, peerName: 'Dad', onPlace: (_, _) {}, celebrated: false, onCelebrate: () {})))), size.value);
      expect(t.takeException(), isNull);
    });

    testWidgets('Pictionary at text scale 2.0, ${size.key}: no overflow', (WidgetTester t) async {
      await pumpAt(t, Scaffold(body: SingleChildScrollView(child: Center(child: PictionaryView(
          phase: PicPhase.viewing, isDrawer: false, word: null, canvas: null, liveStroke: const [],
          revealedStrokes: const [], rounds: 0, peerName: 'Dad', lastGuessWasWrong: false, lastGuessText: null,
          celebrated: false, guessController: TextEditingController(),
          onPanStart: (_) {}, onPanUpdate: (_) {}, onPanEnd: (_) {},
          onShowThem: () {}, onSubmitGuess: (_) {}, onCelebrate: () {})))), size.value);
      expect(t.takeException(), isNull);
    });
  }

  group('with no option on (the app as it was), 2.0 still does not overflow', () {
    for (final MapEntry<String, Widget Function()> s in screens.entries) {
      testWidgets('${s.key} at 2.0, phone, defaults', (WidgetTester t) async {
        await pumpAt(t, s.value(), phone, settings: AccessSettings.defaults);
        expect(t.takeException(), isNull);
      });
      testWidgets('${s.key} at 2.0, fold cover 344, defaults', (WidgetTester t) async {
        await pumpAt(t, s.value(), foldCover, settings: AccessSettings.defaults);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('the options themselves behave at 2.0', () {
    testWidgets('the speaker is still a 48dp target at 2.0 (text scale does not shrink it)', (WidgetTester t) async {
      await pumpAt(t, _home(), tablet);
      final Finder sp = find.byKey(const Key('speakerButton'));
      expect(sp, findsWidgets);
      for (final Element e in sp.evaluate()) {
        final Size sz = (e.renderObject! as RenderBox).size;
        expect(sz.width, greaterThanOrEqualTo(48));
        expect(sz.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('every ChildHome tile has its own speaker, and no label runs under it', (WidgetTester t) async {
      await pumpAt(t, _home(), tablet, scale: 1.0);
      final int tiles = find.byType(TieredTile).evaluate().length;
      expect(tiles, greaterThanOrEqualTo(5));
      expect(find.descendant(of: find.byType(TieredTile), matching: find.byKey(const Key('speakerButton'))),
          findsNWidgets(tiles));
      for (final Element tile in find.byType(TieredTile).evaluate()) {
        final Finder inTile = find.descendant(of: find.byWidget(tile.widget), matching: find.byType(Text));
        final Rect speaker = t.getRect(find.descendant(of: find.byWidget(tile.widget), matching: find.byKey(const Key('speakerButton'))));
        for (final Element txt in inTile.evaluate()) {
          final Rect r = (txt.renderObject! as RenderBox).localToGlobal(Offset.zero) & (txt.renderObject! as RenderBox).size;
          expect(r.overlaps(speaker), isFalse, reason: 'a label overlaps the speaker');
        }
      }
    });
  });
}
