// No longer UNVERIFIED — verified by CI (client/test/play_notice_test.dart).
// OLIVE BRANCH — the ONE calm notice every ad-hoc game shows when the other device is away or the game has finished
// for now, in place of the five separate "_MessageView" copies and their wording.
//
// THE RULES (MASTERFILE section 5.23.2 and P1-P11): no error words (the eleven banned phrases are asserted in the
// test), no blame for either device or the network, no counts, no clock or countdown, no result. Away is not
// ended: a game that is waiting for the other device is simply waiting. The same plain, non-pressuring register
// as the rest of the app ("Nothing is lost").
//
// TWO VOICES (owner, 2026-11-08: "softer words for kids and normal words for the adult side"). PlayWords.child is
// soft, short and picture-friendly: no names, digits, blame or pressure, and a no is never told. PlayWords.adult is
// plain and direct. The voice is chosen by the DEVICE ROLE through PlayAudienceScope (the guardian shell sets it
// to adult; everything else, including a missing scope, is the child's), never by anything a peer sends. All
// semantics are the same in both voices; only the words differ. The child's first name appears in neither.
import 'package:flutter/material.dart';

import 'access_scope.dart' show LiveLine;

enum PlayNoticeKind { none, away, ended }

/// Whose device this is. Set from the device role, never from peer data.
enum PlayAudience { child, adult }

/// Every sentence and label this feature can show, in one voice.
class PlayWords {
  const PlayWords({
    required this.away, required this.ended, required this.resumeFor, required this.resumeYes, required this.resumeNo,
    required this.rematchOffered, required this.rematchYes, required this.rematchNotNow, required this.rematchAsked,
    required this.rematchNeverMind, required this.finishForNow, required this.finishBody, required this.keepPlaying,
    required this.okay, required this.playAgain,
  });
  final String away, ended, resumeYes, resumeNo, rematchOffered, rematchYes, rematchNotNow, rematchAsked,
      rematchNeverMind, finishForNow, finishBody, keepPlaying, okay, playAgain;
  final String Function(String gameTitle) resumeFor;

  /// Soft and short. The game is resting, nothing is lost, and a no is never mentioned.
  static final PlayWords child = PlayWords(
    away: 'Your game is resting. It will wake up when you are together again.',
    ended: 'All done for now. We can play again whenever you like.',
    resumeFor: (String g) => 'Your $g game is still here.',
    resumeYes: 'Carry on', resumeNo: 'Start a new one',
    rematchOffered: 'Play again?', rematchYes: 'Yes', rematchNotNow: 'Not now',
    rematchAsked: 'Asking to play again...', rematchNeverMind: 'Never mind',
    finishForNow: 'Finish for now', finishBody: 'Your game will be saved. We can play again whenever you like.',
    keepPlaying: 'Keep playing', okay: 'Okay', playAgain: 'Play again',
  );

  /// Normal, plain words. An adult may be told plainly what happened.
  static final PlayWords adult = PlayWords(
    away: 'The other device is out of range. The game is saved and will resume when it reconnects.',
    ended: 'The game was ended. It is saved if you want to resume it.',
    resumeFor: (String g) => 'A saved game of $g was found on this device.',
    resumeYes: 'Resume', resumeNo: 'Start a new game',
    rematchOffered: 'The other player asked to play again.', rematchYes: 'Accept', rematchNotNow: 'Decline',
    rematchAsked: 'Asking to play again...', rematchNeverMind: 'Cancel',
    finishForNow: 'Finish for now', finishBody: 'The game is saved. You can start a new one or resume it later.',
    keepPlaying: 'Keep playing', okay: 'OK', playAgain: 'Play again',
  );

  static PlayWords of(PlayAudience a) => a == PlayAudience.adult ? adult : child;

  /// Everything shown in this voice, for the wording audit.
  List<String> all() => <String>[
        away, ended, resumeFor('Uno'), resumeYes, resumeNo, rematchOffered, rematchYes, rematchNotNow, rematchAsked,
        rematchNeverMind, finishForNow, finishBody, keepPlaying, okay, playAgain,
      ];

  String line(PlayNoticeKind kind) => switch (kind) {
        PlayNoticeKind.away => away,
        PlayNoticeKind.ended => ended,
        PlayNoticeKind.none => '',
      };
}

/// The voice for the screens below. The guardian shell sets PlayAudience.adult; no scope means the child's voice
/// (the safe default for a child-facing surface).
class PlayAudienceScope extends InheritedWidget {
  const PlayAudienceScope({super.key, required this.audience, required super.child});
  final PlayAudience audience;

  static PlayAudience of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayAudienceScope>()?.audience ?? PlayAudience.child;
  static PlayWords wordsOf(BuildContext context) => PlayWords.of(of(context));

  @override
  bool updateShouldNotify(PlayAudienceScope old) => old.audience != audience;
}

// The child's voice as plain names (what existing tests and the child-facing code already use).
final String kPlayAwayLine = PlayWords.child.away;
final String kPlayEndedLine = PlayWords.child.ended;
String playResumeLine(String gameTitle) => PlayWords.child.resumeFor(gameTitle);
final String kPlayResumeYes = PlayWords.child.resumeYes;
final String kPlayResumeNo = PlayWords.child.resumeNo;
final String kPlayRematchOffered = PlayWords.child.rematchOffered;
final String kPlayRematchYes = PlayWords.child.rematchYes;
final String kPlayRematchNotNow = PlayWords.child.rematchNotNow;
final String kPlayRematchAsked = PlayWords.child.rematchAsked;
final String kPlayRematchNeverMind = PlayWords.child.rematchNeverMind;
final String kPlayFinishForNow = PlayWords.child.finishForNow;
final String kPlayFinishBody = PlayWords.child.finishBody;
final String kPlayKeepPlaying = PlayWords.child.keepPlaying;
final String kPlayOkay = PlayWords.child.okay;
final String kPlayAgain = PlayWords.child.playAgain;

/// Every user-visible string in the child's voice (kept for the existing wording audit).
List<String> playNoticeStrings() => PlayWords.child.all();

String playNoticeLine(PlayNoticeKind kind) => PlayWords.child.line(kind);

/// The notice itself. Shown in place of the game view while away or ended; the game underneath is untouched.
class PlaySessionNotice extends StatelessWidget {
  const PlaySessionNotice({super.key, required this.kind, this.onLeave});
  final PlayNoticeKind kind;

  /// Offered when the game has ended for now, so the screen can be left with one tap.
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    if (kind == PlayNoticeKind.none) return const SizedBox.shrink();
    final PlayWords w = PlayAudienceScope.wordsOf(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(kind == PlayNoticeKind.away ? Icons.hourglass_empty : Icons.bedtime_outlined, size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(height: 16),
      LiveLine(child: Text(w.line(kind), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge)),
      if (kind == PlayNoticeKind.ended && onLeave != null) ...[
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onLeave, child: Text(w.okay)),
      ],
    ]);
  }
}
