// OLIVE BRANCH — games hub tests. Navigation-wiring-pass addition (see the
// file header in games_hub.dart) — this is the second door onto the boards
// game_picker.dart's own catalogue can't reach (checkers, chess, battleship,
// word search, Kim's game, word chain, scavenger hunt, find the thing).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_checkers.dart';
import 'package:olive_client/game_findthing.dart';
import 'package:olive_client/game_wordsearch.dart';
import 'package:olive_client/games_hub.dart';
import 'package:olive_client/handicap_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('games hub — navigation-wiring pass', () {
    testWidgets('every board in the wiring brief gets a real, tappable tile', (t) async {
      await t.pumpWidget(wrap(const GamesHubScreen()));
      for (final title in <String>[
        'Checkers', 'Chess', 'Battleship', 'Word search', "Kim's game",
        'Word chain', 'Story game', 'Scavenger hunt', 'Find the thing',
        'Play it easier (demo)',
      ]) {
        expect(find.text(title), findsOneWidget, reason: '"$title" tile missing');
      }
    });

    testWidgets('tapping a tile opens the real screen it names, not a stub', (t) async {
      await t.pumpWidget(wrap(const GamesHubScreen(childName: 'Ivy', parentName: 'Dad')));
      await t.tap(find.text('Checkers'));
      await t.pumpAndSettle();
      expect(find.byType(GameCheckers), findsOneWidget);
      final GameCheckers checkers = t.widget(find.byType(GameCheckers));
      expect(checkers.childName, 'Ivy');
      expect(checkers.parentName, 'Dad');
    });

    testWidgets('"Find the thing" is filed under "On her own" — no parent named', (t) async {
      await t.pumpWidget(wrap(const GamesHubScreen()));
      // ensureVisible: this hub's own tile list runs past the default
      // 800x600 test surface, same fold-scrolling issue documented in
      // child_home.dart/guardian_home.dart's own comments — the tile
      // exists in the tree but isn't within tap-hit range until scrolled.
      await t.ensureVisible(find.text('Find the thing'));
      await t.tap(find.text('Find the thing'));
      await t.pumpAndSettle();
      expect(find.byType(GameFindThingScreen), findsOneWidget);
    });

    testWidgets('word search opens the guardian setup screen, never the play screen directly',
        (t) async {
      await t.pumpWidget(wrap(const GamesHubScreen()));
      await t.tap(find.text('Word search'));
      await t.pumpAndSettle();
      expect(find.byType(WordSearchSetupScreen), findsOneWidget);
      expect(find.byType(WordSearchScreen), findsNothing);
    });

    testWidgets('the handicap demo tile opens tic-tac-toe\'s handicap offer', (t) async {
      await t.pumpWidget(wrap(const GamesHubScreen()));
      await t.ensureVisible(find.text('Play it easier (demo)'));
      await t.tap(find.text('Play it easier (demo)'));
      await t.pumpAndSettle();
      expect(find.byType(HandicapScreen), findsOneWidget);
    });

    testWidgets('no settings affordance exists anywhere on the hub', (t) async {
      await t.pumpWidget(wrap(const GamesHubScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('P2 — no score, rank, streak, or leaderboard language on the hub itself', (t) async {
      await t.pumpWidget(wrap(const GamesHubScreen()));
      for (final forbidden in ['streak', 'rank', 'score', 'elo', 'leaderboard']) {
        expect(find.textContaining(RegExp(forbidden, caseSensitive: false)), findsNothing,
            reason: '"$forbidden" must never appear on the games hub');
      }
    });

    testWidgets('hub tiles meet the 48dp+ touch target minimum', (t) async {
      await t.pumpWidget(wrap(const GamesHubScreen()));
      final size = t.getSize(find.widgetWithText(InkWell, 'Checkers').first);
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    group('games dormancy — reached directly while locked (defense in depth; '
        'child_home.dart\'s own tile already refuses to navigate here at all)', () {
      testWidgets('unlocked (default) still shows every tile exactly as before this field existed',
          (t) async {
        await t.pumpWidget(wrap(const GamesHubScreen()));
        expect(find.text('Checkers'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline), findsNothing);
      });

      testWidgets('locked shows a calm, honest message instead of the game list — no dead end',
          (t) async {
        await t.pumpWidget(wrap(const GamesHubScreen(gamesEnabled: false)));
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(find.text('Ask a grown-up to turn on games'), findsOneWidget);
        // The AppBar chrome is still real and present — this isn't a blank
        // dead end, it's an honest, calm alternative body.
        expect(find.text('More games'), findsOneWidget);
      });

      testWidgets('locked shows none of the actual game tiles', (t) async {
        await t.pumpWidget(wrap(const GamesHubScreen(gamesEnabled: false)));
        for (final title in <String>[
          'Checkers', 'Chess', 'Battleship', 'Word search', "Kim's game",
          'Word chain', 'Story game', 'Scavenger hunt', 'Find the thing',
          'Play it easier (demo)',
        ]) {
          expect(find.text(title), findsNothing);
        }
      });

      testWidgets('locked shows no settings/toggle control of any kind', (t) async {
        await t.pumpWidget(wrap(const GamesHubScreen(gamesEnabled: false)));
        expect(find.byType(Switch), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        expect(find.byIcon(Icons.settings), findsNothing);
        expect(find.byIcon(Icons.settings_outlined), findsNothing);
        expect(find.textContaining('Settings'), findsNothing);
      });

      testWidgets('locked hub renders without overflow at the Fold5 cover width (344px)',
          (t) async {
        await t.binding.setSurfaceSize(const Size(344, 882));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const GamesHubScreen(gamesEnabled: false)));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    });

    group('responsive audit — Fold5, phone, and tablet/desktop widths', () {
      // MASTERFILE's own mandated minimum widths (the Fold5's cover and
      // unfolded main screens), plus a standard phone width and a
      // short-and-wide desktop/tablet width now that Windows is a real
      // target. The hub itself is a plain SingleChildScrollView + Column of
      // HubSection/HubTile rows (see hub_widgets.dart), so the risk here is
      // long game titles/subtitles refusing to wrap at the narrowest width.
      for (final MapEntry<String, Size> entry in const <String, Size>{
        'Fold5 cover (344 CSS px)': Size(344, 882),
        'Fold5 unfolded main (~673 CSS px)': Size(673, 841),
        'a standard phone (~390 CSS px)': Size(390, 844),
        'a tablet/desktop (~1100 CSS px)': Size(1100, 800),
      }.entries) {
        testWidgets('renders without overflow at ${entry.key}', (t) async {
          await t.binding.setSurfaceSize(entry.value);
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(wrap(const GamesHubScreen()));
          await t.pump();
          expect(t.takeException(), isNull);
        });
      }
    });
  });
}
