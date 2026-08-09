// OLIVE BRANCH — games hub. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). Navigation-wiring-pass addition,
// not a single MARKUP screen of its own.
//
// game_picker.dart's own catalogue only ever renders cards for its four
// ported GameKind values (tictactoe, dotsboxes, memory, story) and honestly
// falls back to "not built yet" for anything else — by its own file header,
// per-game boards for the other kinds are "other groups' builds". This hub
// is the second door that makes those boards (checkers, chess, battleship,
// word search, Kim's game, word chain, scavenger hunt, find the thing)
// actually reachable, without game_picker.dart ever needing to import them.
//
// child_home.dart's "Play together" tile still goes straight to
// GamePickerScreen, per the wiring brief; "More games" opens this instead.
//
// Games dormancy (db/migrations/0008_games_access.sql): child_home.dart's
// own "More games" tile already refuses to navigate here at all while
// locked (it shows its own passive locked state and never pushes this
// route — see that file). `gamesEnabled` exists on THIS screen too, purely
// as defense in depth for the case this is reached some other way (a deep
// link, a future call site, a test constructing it directly) — "reached
// directly" bypassing that gate. Defaults to `true` so every existing call
// site and test that predates this field keeps rendering exactly as before.
import 'package:flutter/material.dart';
import 'game_battleship.dart';
import 'game_chain.dart';
import 'game_checkers.dart';
import 'game_chess.dart';
import 'game_findthing.dart';
import 'game_hunt.dart';
import 'game_kim.dart';
import 'game_logic.dart';
import 'game_story.dart';
import 'game_wordsearch.dart';
import 'handicap_screen.dart';
import 'hub_widgets.dart';

class GamesHubScreen extends StatelessWidget {
  const GamesHubScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad',
    this.gamesEnabled = true});
  final String childName;
  final String parentName;
  final bool gamesEnabled;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More games')),
    body: SafeArea(child: gamesEnabled ? _hubBody(context) : const _GamesLocked()),
  );

  Widget _hubBody(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        HubSection(title: 'Board & strategy', children: [
          HubTile(icon: Icons.grid_on, title: 'Checkers',
            subtitle: 'Async by nature — survives a dropped call',
            onTap: () => _open(context, GameCheckers(childName: childName, parentName: parentName))),
          HubTile(icon: Icons.castle_outlined, title: 'Chess',
            subtitle: 'Real rules, real engine, patient by design',
            onTap: () => _open(context, GameChess(childName: childName, parentName: parentName))),
          HubTile(icon: Icons.sailing_outlined, title: 'Battleship',
            subtitle: 'Hers and his boards, never both on one screen',
            onTap: () => _open(context, GameBattleship(childName: childName, parentName: parentName))),
        ]),
        HubSection(title: 'Together', children: [
          HubTile(icon: Icons.search, title: 'Word search',
            subtitle: 'Words from her own week',
            onTap: () => _open(context, WordSearchSetupScreen(childName: childName))),
          HubTile(icon: Icons.visibility_outlined, title: "Kim's game",
            subtitle: 'Memory play with their own shared things',
            onTap: () => _open(context, GameKim(childName: childName, parentName: parentName))),
          HubTile(icon: Icons.link, title: 'Word chain',
            subtitle: 'A game that grows across custody weeks',
            onTap: () => _open(context, GameChainScreen(childName: childName, parentName: parentName))),
          HubTile(icon: Icons.auto_stories_outlined, title: 'Story game',
            subtitle: 'A turn-by-turn tale between them',
            onTap: () => _open(context, GameStoryScreen(childName: childName, parentName: parentName))),
          HubTile(icon: Icons.travel_explore, title: 'Scavenger hunt',
            subtitle: 'He hides it in her world',
            onTap: () => _open(context, GameHuntScreen(childName: childName, parentName: parentName))),
        ]),
        HubSection(title: 'On her own', children: [
          HubTile(icon: Icons.zoom_in, title: 'Find the thing',
            subtitle: 'A packed, zoomable scene',
            onTap: () => _open(context, const GameFindThingScreen())),
        ]),
        HubSection(title: 'Playing fair', children: [
          HubTile(icon: Icons.balance, title: 'Play it easier (demo)',
            subtitle: 'She sets a handicap for a grown-up — never the other way',
            onTap: () => _open(context, const HandicapScreen(kind: GameKind.tictactoe))),
        ]),
      ]));
}

/// Calm, honest locked state for this screen being reached while games are
/// dormant (see file header). Same icon-plus-text tone
/// child_home_live.dart's own "Couldn't reach the server" state already
/// uses for "the real thing isn't available right now" — a real icon, a
/// short real sentence, no fabricated detail, no settings control anywhere
/// on it (there is nothing to tap here at all).
class _GamesLocked extends StatelessWidget {
  const _GamesLocked();
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.lock_outline, size: 40, color: Theme.of(context).colorScheme.outline),
      const SizedBox(height: 12),
      const Text('Ask a grown-up to turn on games',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w600)),
    ]),
  ));
}
