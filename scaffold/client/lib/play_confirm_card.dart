// OLIVE BRANCH — the grown-up's confirmation when a paired device first connects to play. UNVERIFIED on a device;
// widget-tested headless (client/test/play_admission_test.dart). Research section 5.2; play_admission.dart.
//
// Shown ONLY on the grown-up's device (the child's device never asks: the pinned adult is its authority). Plain
// words, the same word and picture the other screen shows, one tap to say yes. No codes are typed or read aloud
// by a child; nothing the peer sent is shown except through [sanitizePeerText].
import 'package:flutter/material.dart';

import 'child_connect_screen.dart' show kSasIcons;
import 'play_admission.dart';

class PlayConfirmCard extends StatelessWidget {
  const PlayConfirmCard({super.key, required this.admission, this.peerSeat = 2});
  final PlayAdmission admission;

  /// Which seat the other device holds. The ONLY thing the card calls it: "Player one" or "Player two". No name, no
  /// model, nothing the peer sent is rendered.
  final int peerSeat;

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
                Text('${seatLabel(peerSeat)} wants to join', style: Theme.of(context).textTheme.titleMedium),
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
