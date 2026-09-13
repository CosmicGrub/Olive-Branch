// OLIVE BRANCH — the one real switch from a GameKind to its real board.
// UNVERIFIED (no Flutter toolchain in tools/verify.sh's automated
// pipeline). MASTERFILE §9.2.
//
// Extracted so child_home.dart's real wiring and guardian_more.dart's own
// (added when the two sides' "Play together" catalogues were consolidated
// into one section, reachable from both — see game_picker.dart's own
// [GamePickerScreen.extraSections] and games_hub.dart's own
// [MoreGamesSections]) can never drift apart the way two independently
// hand-maintained copies of the same switch eventually would. Real cases
// for every game this codebase has actually built a board for — Batch C's
// own two (copyPattern/findIt, the closing batch of Play Together Phase
// 1), Batch B's four (sillySentence/wouldYouRather/twoTruths/
// twentyQuestions), Batch A's two (drawTogether/guessDoodle), and a
// parallel build's (tictactoe/dotsboxes). `memory` alone stays on the
// honest not-built-yet fallback — a separate, still-open photo-source
// product decision, deliberately out of scope for this file (see
// game_logic.dart's own note).
import 'package:flutter/material.dart';
import 'game_copy_pattern.dart';
import 'game_dotsboxes.dart';
import 'game_draw_together.dart';
import 'game_find_it.dart';
import 'game_guess_doodle.dart';
import 'game_logic.dart';
import 'game_silly_sentence.dart';
import 'game_story.dart';
import 'game_tictactoe.dart';
import 'game_twenty_questions.dart';
import 'game_two_truths.dart';
import 'game_would_you_rather.dart';

/// Honest acknowledgment for a game this build has no board for yet — the
/// same "recorded, not glossed over" posture the rest of this project
/// already takes for unbuilt surfaces (child_home.dart's own
/// `_notBuiltYet`, mirrored here rather than imported, since a private
/// top-level function can't cross a file boundary and this is the only
/// place in this file that needs it).
void _notBuiltYet(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

/// Builds a real onPlay callback for [GamePickerScreen]/[GameCatalogueGrid],
/// bound to one child's real name. Both real call sites — child_home.dart's
/// own "Play together" tile and guardian_more.dart's mirrored one — pass
/// this straight through rather than each maintaining their own copy of the
/// switch.
void Function(BuildContext context, GameKind kind) buildGameNavigator(String childName) {
  return (playContext, kind) {
    switch (kind) {
      case GameKind.story:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => GameStoryScreen(childName: childName)));
      case GameKind.tictactoe:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => GameTicTacToe(childName: childName)));
      case GameKind.dotsboxes:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => GameDotsBoxes(childName: childName)));
      case GameKind.drawTogether:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => DrawTogetherScreen(childName: childName)));
      case GameKind.guessDoodle:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => GuessDoodleScreen(childName: childName)));
      case GameKind.sillySentence:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => SillySentenceScreen(childName: childName)));
      case GameKind.wouldYouRather:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => WouldYouRatherScreen(childName: childName)));
      case GameKind.twoTruths:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => TwoTruthsScreen(childName: childName)));
      case GameKind.twentyQuestions:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => TwentyQuestionsScreen(childName: childName)));
      case GameKind.copyPattern:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => CopyPatternScreen(childName: childName)));
      case GameKind.findIt:
        Navigator.of(playContext).push(MaterialPageRoute<void>(
          builder: (_) => const FindItScreen()));
      case GameKind.memory:
        _notBuiltYet(playContext, 'That game');
    }
  };
}
