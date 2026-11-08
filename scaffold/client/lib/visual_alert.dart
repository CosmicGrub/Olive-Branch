// OLIVE BRANCH — the one way a child screen tells her something happened. No
// longer UNVERIFIED — verified by CI (client/test/visual_alert_test.dart).
//
// NO CUE IS SOUND ONLY. This file makes no sound at all: every alert is a picture
// and words. By default it is a brief note at the bottom of the screen. When "alerts
// she can see" is on (AccessSettings.visualAlerts, set by a guardian or by the
// Compass profile) it is a banner with a picture and words that STAYS until she taps
// it, with a gentle buzz. Nothing here ever flashes, for anyone, and nothing moves
// by itself (AlertCue.flashes is false and a test holds it).
//
// It reads only the child-readable accessibility settings through AccessScope, so
// a child screen never learns why (no profile, no label about her).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'access_scope.dart';
import 'compass_logic.dart';

/// Shows the cue for [kind]. Returns nothing: it is information, not a task.
void showAlertCue(BuildContext context, AlertKind kind) {
  final AlertCue cue = cueFor(AccessScope.of(context), kind);
  final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
  if (cue.haptic) HapticFeedback.mediumImpact();
  if (cue.persistent) {
    m.clearMaterialBanners();
    m.showMaterialBanner(MaterialBanner(
      key: const Key('visualAlert'),
      leading: const Icon(Icons.notifications_active_outlined, size: 32),
      content: Text(cue.text, style: Theme.of(context).textTheme.titleMedium),
      actions: <Widget>[
        TextButton(
          key: const Key('visualAlertOk'),
          style: TextButton.styleFrom(minimumSize: const Size(64, 64)),
          onPressed: () => m.hideCurrentMaterialBanner(),
          child: const Text('OK'),
        ),
      ],
    ));
  } else {
    m.showSnackBar(SnackBar(
      key: const Key('visualAlert'),
      content: Row(children: <Widget>[
        const Icon(Icons.notifications_none_outlined),
        const SizedBox(width: 10),
        Expanded(child: Text(cue.text)),
      ]),
      duration: const Duration(seconds: 3),
    ));
  }
}

/// Clears a banner a screen left up (call from dispose, so it does not follow her
/// to another screen).
void clearAlertCues(ScaffoldMessengerState m) => m.clearMaterialBanners();
