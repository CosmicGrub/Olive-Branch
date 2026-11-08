// OLIVE BRANCH — games hub. No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs
// for real in tools/verify.sh's automated pipeline — CHANGELOG v0.49.61).
// Navigation-wiring-pass addition, not a single MARKUP screen of its own.
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
// child_home.dart's own "Play together" tile now opens GamePickerScreen
// WITH [MoreGamesSections] passed as its extraSections — see that file's
// own doc comment — so every choice she has lives in the one screen, not
// split behind a separate "More games" door. GamesHubScreen below still
// exists, unchanged in its own right, for any caller (a test, a future
// standalone entry point) that wants just this half on its own.
import 'package:flutter/material.dart';
import 'activity_overrides.dart';
import 'game_battleship.dart';
import 'game_chain.dart';
import 'game_checkers.dart';
import 'game_chess.dart';
import 'game_connect4.dart';
import 'game_findthing.dart';
import 'game_hangman.dart';
import 'game_hunt.dart';
import 'game_pictionary.dart';
import 'game_puzzle.dart';
import 'game_uno.dart';
import 'game_war.dart';
import 'game_kim.dart';
import 'game_logic.dart';
import 'game_story.dart';
import 'game_wordsearch.dart';
import 'handicap_screen.dart';
import 'hub_widgets.dart';
import 'networked_checkers_lobby_screen.dart';

void _open(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

/// The real sections themselves, factored out of [GamesHubScreen] so
/// game_picker.dart's own consolidated screen can render them as its
/// `extraSections` without a second, hand-copied wiring list drifting from
/// this one. Pure extraction — same widget tree this file always produced,
/// just reachable by a second caller now.
class MoreGamesSections extends StatelessWidget {
  const MoreGamesSections({
    super.key, this.childName = 'Ivy', this.parentName = 'Dad',
    this.childAge = 7, this.overrides,
    this.guardianSide = false, this.localRole = 'ivy',
  });
  final String childName;
  final String parentName;

  // Parental controls, visibility & pacing (docs/superpowers/specs/2026-09-
  // 13-parental-controls-pacing-design.md) — the 8 games this pass gives a
  // real minAge (game_logic.dart's own `hubGameMinAge`), plus visibility for
  // "Find the thing" (no age concept — Explicitly out of scope, per that
  // spec, for a surface that never had one). [childAge] defaults to 7,
  // matching game_picker.dart's own pre-existing default; [overrides] null
  // means no live session at all, and every game/activity below renders
  // exactly as it did before this feature existed.
  final int childAge;
  final Map<String, ActivityOverride>? overrides;

  /// True only when a GUARDIAN opened this hub (guardian_more.dart). Word
  /// search and Guess-the-word start on a grown-up's own SETUP screen (the
  /// adult types the words in), which is guardian-facing UI — C-14 keeps it
  /// off the child shell entirely (§8.1: nothing guardian-facing reachable
  /// from the child shell), so the child hub never lists them.
  final bool guardianSide;

  /// Which real identity this device plays in the ad-hoc "on this table"
  /// games ('ivy' = the child's side, anything else = the grown-up's side;
  /// local_pairing.dart's own `mySide` rule). The child shell keeps the
  /// default, guardian_more.dart passes 'dad'.
  final String localRole;

  bool _hubGameVisible(String key) => effectiveVisibility(
        overrides: overrides, activityKey: 'game:$key', childAge: childAge,
        defaultMinAge: hubGameMinAge[key] ?? 0,
      );

  bool _localVisible(String key) => childAge >= (localPlayMinAge[key] ?? 0);

  // Child-voice wording (C-13, C-12): short, second person, no grown-up
  // planning language, and honest about WHO she plays against. The board
  // games below run on THIS screen against the game itself — the second
  // player is a stand-in, not a live grown-up — so the line says that
  // plainly instead of implying a person is on the other end. The live
  // checkers line is the one that really is two devices.
  @override
  Widget build(BuildContext context) {
    final String localName = localRole == 'ivy' ? childName : parentName;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    HubSection(title: 'Board games', children: [
      if (_hubGameVisible('checkers')) ...[
        HubTile(readAloud: !guardianSide, icon: Icons.grid_on, title: 'Checkers',
          subtitle: 'You against the game, on this screen',
          onTap: () => _open(context, GameCheckers(childName: childName, parentName: parentName))),
        HubTile(readAloud: !guardianSide, icon: Icons.wifi_tethering, title: 'Checkers on two screens',
          subtitle: 'One game, played from two screens',
          onTap: () => _open(context, const NetworkedCheckersLobbyScreen())),
      ],
      if (_hubGameVisible('chess'))
        HubTile(readAloud: !guardianSide, icon: Icons.castle_outlined, title: 'Chess',
          subtitle: 'You against the game, on this screen',
          onTap: () => _open(context, GameChess(childName: childName, parentName: parentName))),
      if (_hubGameVisible('battleship'))
        HubTile(readAloud: !guardianSide, icon: Icons.sailing_outlined, title: 'Battleship',
          subtitle: 'Hunt for hidden ships, on this screen',
          onTap: () => _open(context, GameBattleship(childName: childName, parentName: parentName))),
    ]),
    HubSection(title: 'Words and looking', children: [
      if (guardianSide && _hubGameVisible('wordsearch'))
        HubTile(readAloud: !guardianSide, icon: Icons.search, title: 'Word search',
          subtitle: 'Set up a puzzle from words in their week',
          onTap: () => _open(context, WordSearchSetupScreen(childName: childName))),
      if (_hubGameVisible('kimsGame'))
        HubTile(readAloud: !guardianSide, icon: Icons.visibility_outlined, title: "Kim's game",
          subtitle: 'Look closely, then spot what is gone',
          onTap: () => _open(context, GameKim(childName: childName, parentName: parentName))),
      if (_hubGameVisible('wordChain'))
        HubTile(readAloud: !guardianSide, icon: Icons.link, title: 'Word chain',
          subtitle: 'Add a word to the chain',
          onTap: () => _open(context, GameChainScreen(childName: childName, parentName: parentName))),
      if (guardianSide && _hubGameVisible('hangman'))
        HubTile(readAloud: !guardianSide, icon: Icons.abc, title: 'Guess the word',
          subtitle: 'Choose a word for them to guess',
          onTap: () => _open(context, HangmanSetupScreen(childName: childName))),
      HubTile(readAloud: !guardianSide, icon: Icons.auto_stories_outlined, title: 'Story game',
        subtitle: 'Make up a story, one line each',
        onTap: () => _open(context, GameStoryScreen(childName: childName, parentName: parentName))),
      if (_hubGameVisible('scavengerHunt'))
        HubTile(readAloud: !guardianSide, icon: Icons.travel_explore, title: 'Scavenger hunt',
          subtitle: 'Hunt for hidden things',
          onTap: () => _open(context, GameHuntScreen(childName: childName, parentName: parentName))),
    ]),
    // C-11: the five ad-hoc games that were hardware-verified (two real
    // devices, same wifi, no internet needed — local_pairing.dart) but had no
    // door outside their dev-only main_*_test.dart entry points. Each screen
    // is posture-aware on its own (foldTabletop/tabletSmall layouts), so this
    // section only has to open them.
    HubSection(title: 'Play together on this table', children: [
      if (_localVisible('war'))
        HubTile(readAloud: !guardianSide, icon: Icons.style_outlined, title: 'War',
          subtitle: 'Flip your cards, biggest card wins',
          onTap: () => _open(context, GameWarScreen(role: localRole, displayName: localName))),
      if (_localVisible('connect4'))
        HubTile(readAloud: !guardianSide, icon: Icons.apps, title: 'Connect 4',
          subtitle: 'Drop discs, get four in a row',
          onTap: () => _open(context, GameConnect4Screen(role: localRole, displayName: localName))),
      if (_localVisible('uno'))
        HubTile(readAloud: !guardianSide, icon: Icons.filter_none, title: 'Uno',
          subtitle: 'Match the colour or the number',
          onTap: () => _open(context, GameUnoScreen(role: localRole, displayName: localName))),
      if (_localVisible('pictionary'))
        HubTile(readAloud: !guardianSide, icon: Icons.draw_outlined, title: 'Draw and guess',
          subtitle: 'One draws, the other guesses',
          onTap: () => _open(context, GamePictionaryScreen(role: localRole, displayName: localName))),
      if (_localVisible('puzzle'))
        HubTile(readAloud: !guardianSide, icon: Icons.extension_outlined, title: 'Puzzle together',
          subtitle: 'Put the pieces in, side by side',
          onTap: () => _open(context, GamePuzzleScreen(role: localRole, displayName: localName))),
    ]),
    HubSection(title: 'On your own', children: [
      if (isTileVisible(overrides, 'game:findthing'))
        HubTile(readAloud: !guardianSide, icon: Icons.zoom_in, title: 'Find the thing',
          subtitle: 'Spot things in a busy picture',
          onTap: () => _open(context, const GameFindThingScreen())),
    ]),
    // §9.2: a handicap is set by the child, on the grown-up, never the other
    // way round — so the grown-up's own hub does not offer it at all.
    if (!guardianSide)
      HubSection(title: 'Make it fair', children: [
        HubTile(readAloud: !guardianSide, icon: Icons.balance, title: 'Make it harder for $parentName',
          subtitle: 'Pick a tricky rule, just for them',
          onTap: () => _open(context, HandicapScreen(kind: GameKind.tictactoe, parentName: parentName))),
      ]),
  ]);
  }
}

class GamesHubScreen extends StatelessWidget {
  const GamesHubScreen({
    super.key, this.childName = 'Ivy', this.parentName = 'Dad',
    this.childAge = 7, this.overrides,
    this.guardianSide = false, this.localRole = 'ivy',
  });
  final String childName;
  final String parentName;
  final int childAge;
  final Map<String, ActivityOverride>? overrides;
  /// See [MoreGamesSections.guardianSide] / [MoreGamesSections.localRole].
  final bool guardianSide;
  final String localRole;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More games')),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MoreGamesSections(childName: childName, parentName: parentName,
        childAge: childAge, overrides: overrides,
        guardianSide: guardianSide, localRole: localRole),
    )),
  );
}
