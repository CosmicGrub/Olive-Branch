// No longer UNVERIFIED — verified by CI (client/test/play_notice_test.dart).
// OLIVE BRANCH — the ONE calm notice every ad-hoc game shows when the other device is away or the game has finished
// for now, in place of the five separate "_MessageView" copies and their wording.
//
// THE RULES (MASTERFILE section 5.23.2 and P1-P11): no error words (the eleven banned phrases are asserted in the
// test), no blame for either device or the network, no counts, no clock or countdown, no result. Away is not
// ended: a game that is waiting for the other device is simply waiting. The same plain, non-pressuring register
// as the rest of the app ("Nothing is lost").
//
// THE WORDING BELOW IS A DRAFT FOR THE OWNER TO APPROVE (listed in the PR description). It is deliberately free
// of names: the child's first name travels no further than it already does.
import 'package:flutter/material.dart';

import 'access_scope.dart' show LiveLine;

enum PlayNoticeKind { none, away, ended }

/// Shown while the other device is out of reach. The game is kept and carries on by itself.
const String kPlayAwayLine = 'Your game is safe. Nothing is lost. It will carry on when you are close again.';

/// Shown when the game has finished for now (the other side chose to stop, or a long quiet passed).
const String kPlayEndedLine = 'This game has finished for now. Nothing is lost, and you can start again whenever you like.';

/// Offered to the grown-up on the dealing device when a saved game is found.
String playResumeLine(String gameTitle) => 'There is a game of $gameTitle saved on this phone.';
const String kPlayResumeYes = 'Carry on';
const String kPlayResumeNo = 'Start a new one';

/// Rematch, either side may ask and the other chooses. Neither side is told the other said no.
const String kPlayRematchOffered = 'Play again?';
const String kPlayRematchYes = 'Yes';
const String kPlayRematchNotNow = 'Not now';
const String kPlayRematchAsked = 'Asked to play again.';
const String kPlayRematchNeverMind = 'Never mind';
const String kPlayFinishForNow = 'Finish for now';
const String kPlayFinishBody = 'Nothing is lost. You can start again whenever you like.';
const String kPlayKeepPlaying = 'Keep playing';
const String kPlayOkay = 'Okay';
const String kPlayAgain = 'Play again';

/// Every user-visible string this feature can show, for the wording audit.
List<String> playNoticeStrings() => <String>[
      kPlayAwayLine, kPlayEndedLine, playResumeLine('Uno'), kPlayResumeYes, kPlayResumeNo,
      kPlayRematchOffered, kPlayRematchYes, kPlayRematchNotNow, kPlayRematchAsked, kPlayRematchNeverMind,
      kPlayFinishForNow, kPlayFinishBody, kPlayKeepPlaying, kPlayOkay, kPlayAgain,
    ];

String playNoticeLine(PlayNoticeKind kind) => switch (kind) {
      PlayNoticeKind.away => kPlayAwayLine,
      PlayNoticeKind.ended => kPlayEndedLine,
      PlayNoticeKind.none => '',
    };

/// The notice itself. Shown in place of the game view while away or ended; the game underneath is untouched.
class PlaySessionNotice extends StatelessWidget {
  const PlaySessionNotice({super.key, required this.kind, this.onLeave});
  final PlayNoticeKind kind;

  /// Offered when the game has ended for now, so the screen can be left with one tap.
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    if (kind == PlayNoticeKind.none) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(kind == PlayNoticeKind.away ? Icons.hourglass_empty : Icons.bedtime_outlined, size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(height: 16),
      LiveLine(child: Text(playNoticeLine(kind), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge)),
      if (kind == PlayNoticeKind.ended && onLeave != null) ...[
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onLeave, child: const Text(kPlayOkay)),
      ],
    ]);
  }
}
