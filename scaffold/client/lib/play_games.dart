// No longer UNVERIFIED — verified by CI (client/test/play_registry_test.dart).
// OLIVE BRANCH — the registry of ad-hoc "Play together" games that run on the shared contract (play_game.dart).
//
// MIGRATED: War, Connect 4 and Uno (their two-device play). NOT YET (each keeps working exactly as before on its own
// dialect; the migration path for every one is mechanical, see the PR description): Draw and guess (game_pictionary.dart),
// Puzzle together (game_puzzle.dart) and Twenty Questions (local_play_screen.dart). A game moves over by: giving its
// engine a [PlayGame] that answers stateFor / onMove / applyState, registering its [PlayGameSpec] here, and deleting its
// own payload parsing, peer-lost view and send helper. The hub tiles and the age tables (games_hub.dart,
// game_logic.dart localPlayMinAge) are untouched; a test checks the registry's ages against that table so they cannot drift.
import 'connect4_play.dart';
import 'game_war.dart' show warSpec;
import 'live_games.dart' show liveForbidden;
import 'play_game.dart';
import 'uno_play.dart';

PlayRegistry _build() {
  final PlayRegistry r = PlayRegistry();
  for (final PlayGameSpec s in <PlayGameSpec>[warSpec, connect4Spec, unoSpec]) {
    r.register(s, forbidden: liveForbidden);
  }
  return r;
}

/// Every game that runs on the shared contract.
final PlayRegistry playGameRegistry = _build();
