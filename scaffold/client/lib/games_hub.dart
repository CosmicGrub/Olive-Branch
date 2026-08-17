// OLIVE BRANCH — games hub. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). Navigation-wiring-pass addition,
// not a single MARKUP screen of its own.
//
// game_picker.dart's own catalogue only ever renders cards for its four
// ported GameKind values (tictactoe, dotsboxes, memory, story) and honestly
// falls back to "not built yet" for anything else — by its own file header,
// per-game boards for the other kinds are "other groups' builds". This hub
// is the second door that makes those boards (checkers, chess, battleship,
// word search, Kim's game, word chain, guess-the-word, scavenger hunt, find
// the thing) actually reachable, without game_picker.dart ever needing to
// import them.
//
// child_home.dart's "Play together" tile still goes straight to
// GamePickerScreen, per the wiring brief; "More games" opens this instead.
import 'package:flutter/material.dart';
import 'game_battleship.dart';
import 'game_chain.dart';
import 'game_checkers.dart';
import 'game_chess.dart';
import 'game_findthing.dart';
import 'game_hangman.dart';
import 'game_hunt.dart';
import 'game_kim.dart';
import 'game_logic.dart';
import 'game_story.dart';
import 'game_wordsearch.dart';
import 'handicap_screen.dart';
import 'hub_widgets.dart';

class GamesHubScreen extends StatelessWidget {
  const GamesHubScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad'});
  final String childName;
  final String parentName;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More games')),
    body: SafeArea(child: SingleChildScrollView(
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
          HubTile(icon: Icons.abc, title: 'Guess the word',
            subtitle: 'A word chosen by you, and personal',
            onTap: () => _open(context, HangmanSetupScreen(childName: childName))),
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
      ]),
    )),
  );
}
