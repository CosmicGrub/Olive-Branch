// OLIVE BRANCH — games hub tests. Navigation-wiring-pass addition (see the
// file header in games_hub.dart) — this is the second door onto the boards
// game_picker.dart's own catalogue can't reach (checkers, chess, battleship,
// word search, Kim's game, word chain, scavenger hunt, find the thing).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/activity_overrides.dart';
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

    group('parental controls, visibility & pacing — the 8 newly-minAge\'d games', () {
      // GamesHubScreen (not the bare MoreGamesSections) — its own
      // SingleChildScrollView is what keeps this file's other tests from
      // overflowing the default test viewport; matches every other test in
      // this file.
      testWidgets('at childAge 3 (below every one of the 8 real minAge values), none of them render',
          (t) async {
        await t.pumpWidget(wrap(const GamesHubScreen(childAge: 3)));
        for (final title in <String>[
          'Checkers', 'Chess', 'Battleship', 'Word search', "Kim's game",
          'Word chain', 'Guess the word', 'Scavenger hunt',
        ]) {
          expect(find.text(title), findsNothing, reason: '"$title" should be paced out at age 3');
        }
        // "Story game" has no age concept at all — untouched by this pass.
        expect(find.text('Story game'), findsOneWidget);
      });

      testWidgets('a guardian-hidden game (visible:false) never renders, even at an eligible age',
          (t) async {
        await t.pumpWidget(wrap(const GamesHubScreen(
          childAge: 10,
          overrides: {'game:checkers': ActivityOverride(activityKey: 'game:checkers', visible: false)},
        )));
        expect(find.text('Checkers'), findsNothing);
        // An unrelated, still-eligible game is untouched.
        expect(find.text('Chess'), findsOneWidget);
      });

      testWidgets('a guardian reveal resurrects a game its own real minAge would have excluded',
          (t) async {
        await t.pumpWidget(wrap(const GamesHubScreen(childAge: 0)));
        // Sanity: at childAge 0 with no override at all, checkers (real
        // minAge 6) is excluded.
        expect(find.text('Checkers'), findsNothing);

        await t.pumpWidget(wrap(GamesHubScreen(
          childAge: 0,
          overrides: {'game:checkers': ActivityOverride(activityKey: 'game:checkers', revealedAt: DateTime.now())},
        )));
        expect(find.text('Checkers'), findsOneWidget);
      });

      testWidgets('"Find the thing" (no age concept) is visibility-only', (t) async {
        await t.pumpWidget(wrap(const GamesHubScreen(
          childAge: 0,
          overrides: {'game:findthing': ActivityOverride(activityKey: 'game:findthing', visible: false)},
        )));
        expect(find.text('Find the thing'), findsNothing);
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
