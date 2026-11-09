// No longer UNVERIFIED — verified by CI (client/test/play_notice_test.dart).
// OLIVE BRANCH — the small widgets every ad-hoc game shares, so the away line, the rematch ask and "Finish for now"
// are written once and worded once (play_notice.dart). They only read a [PlaySessionController]; the screens
// already rebuild when it changes.
//
// Calm by construction: no error icon, no red, no count, no clock. Away is a line above the game, not a replacement for it.
import 'package:flutter/material.dart';

import 'access_scope.dart' show LiveLine;
import 'play_notice.dart';
import 'play_session.dart';

/// One calm line above the game while the other device is away. Nothing when it is not.
class PlayAwayBanner extends StatelessWidget {
  const PlayAwayBanner({super.key, required this.session});
  final PlaySessionController session;

  @override
  Widget build(BuildContext context) {
    if (session.notice == PlayNoticeKind.none) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LiveLine(child: Text(playNoticeLine(session.notice), textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
    );
  }
}

/// "Play again" once a game is finished. Either side may ask; the other chooses. Neither is told a no.
class PlayRematchBar extends StatelessWidget {
  const PlayRematchBar({super.key, required this.session});
  final PlaySessionController session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (session.rematch) {
      case PlayRematch.none:
        return Padding(padding: const EdgeInsets.only(top: 20),
          child: FilledButton(onPressed: session.askRematch, child: const Text(kPlayAgain)));
      case PlayRematch.asked:
        return Padding(padding: const EdgeInsets.only(top: 20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          LiveLine(child: Text(kPlayRematchAsked, style: theme.textTheme.bodyLarge)),
          TextButton(onPressed: session.cancelRematchAsk, child: const Text(kPlayRematchNeverMind)),
        ]));
      case PlayRematch.offered:
        return Padding(padding: const EdgeInsets.only(top: 20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          LiveLine(child: Text(kPlayRematchOffered, style: theme.textTheme.titleMedium)),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(onPressed: session.acceptRematch, child: const Text(kPlayRematchYes)),
            const SizedBox(width: 12),
            TextButton(onPressed: session.declineRematch, child: const Text(kPlayRematchNotNow)),
          ]),
        ]));
    }
  }
}

/// The grown-up's way to stop for now: tells the other device, and clears the saved game on this one.
class PlayFinishButton extends StatelessWidget {
  const PlayFinishButton({super.key, required this.session});
  final PlaySessionController session;

  @override
  Widget build(BuildContext context) {
    if (!session.hasMetPeer || session.endedForGood) return const SizedBox.shrink();
    return IconButton(
      tooltip: kPlayFinishForNow,
      icon: const Icon(Icons.pause_circle_outline),
      onPressed: () async {
        final bool? yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text(kPlayFinishForNow),
            content: const Text(kPlayFinishBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(kPlayKeepPlaying)),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text(kPlayFinishForNow)),
            ],
          ),
        );
        if (yes == true) await session.finishForNow();
      },
    );
  }
}

/// Asked of the grown-up on the dealing device when a saved game is found: carry on, or start a new one.
Future<bool> askResumeSavedGame(BuildContext context, String gameTitle) async {
  final bool? yes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      content: Text(playResumeLine(gameTitle)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(kPlayResumeNo)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text(kPlayResumeYes)),
      ],
    ),
  );
  return yes == true;
}
