// OLIVE BRANCH — the grown-up's confirmation when a paired device first connects to play. UNVERIFIED on a device;
// widget-tested headless (client/test/play_admission_test.dart). Research section 5.2; play_admission.dart.
//
// Shown ONLY on the grown-up's device (the child's device never asks: the pinned adult is its authority). Plain
// words, the same word and picture the other screen shows, one tap to say yes. No codes are typed or read aloud
// by a child; nothing the peer sent is shown except through [sanitizePeerText].
import 'package:flutter/material.dart';

import 'child_connect_screen.dart' show kSasIcons;
import 'local_pairing.dart';
import 'play_admission.dart';

class PlayConfirmCard extends StatelessWidget {
  const PlayConfirmCard({super.key, required this.admission, this.peerSeat = 2});
  final PlayAdmission admission;

  /// Which seat the other device holds. The ONLY thing the card calls it: "Player one" or "Player two". No name, no
  /// model, nothing the peer sent is rendered.
  final int? peerSeat;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: admission,
        builder: (BuildContext context, Widget? _) {
          if (admission.state != PlayState.awaitingConfirm || admission.sas == null) return const SizedBox.shrink();
          final sas = admission.sas!;
          return Card(
            key: const Key('playConfirmCard'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Text(peerSeat == null ? 'The other device wants to join' : '${seatLabel(peerSeat!)} wants to join',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('Is the same word and picture on their screen?'),
                const SizedBox(height: 8),
                Icon(kSasIcons[sas.picture] ?? Icons.star_rounded, size: 48, key: const Key('playConfirmPicture')),
                Text(sas.word, key: const Key('playConfirmWord'), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                  OutlinedButton(key: const Key('playConfirmNo'), onPressed: admission.decline, child: const Text('No')),
                  const SizedBox(width: 12),
                  FilledButton(key: const Key('playConfirmYes'), onPressed: admission.confirm, child: const Text('Yes, let them in')),
                ]),
              ]),
            ),
          );
        },
      );
}

/// Wraps a game screen on EVERY device and shows the confirmation card over it on a grown-up's device when a paired
/// device connects for the first time (the game screen underneath carries on waiting). On a child's device the
/// admission never asks, so this is just [child]: a child is never shown the card, a question, or a code.
class PlayConfirmOverlay extends StatelessWidget {
  const PlayConfirmOverlay({super.key, required this.pairing, required this.child});

  /// Null before a game has opened its pairing (Connect 4 opens it only when "Play nearby" is chosen).
  final LocalPairingController? pairing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final LocalPairingController? p = pairing;
    if (p == null) return child;
    return ListenableBuilder(
        listenable: p,
        builder: (BuildContext context, Widget? _) {
          final PlayAdmission? adm = p.admission;
          if (adm == null || !p.awaitingGrownUp) return child;
          return Stack(children: <Widget>[
            child,
            const Positioned.fill(child: ModalBarrier(dismissible: false, color: Color(0x99000000))),
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: PlayConfirmCard(admission: adm, peerSeat: p.peerSeat),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
  }
}
