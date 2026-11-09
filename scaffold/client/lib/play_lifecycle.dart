// OLIVE BRANCH — closes the play socket when the app leaves the foreground. UNVERIFIED on a device; the observer is
// tested headless (client/test/play_lifecycle_test.dart). Owner requirement 2026-11-08: the listening socket "opens only
// during an admitted/pending session window, closes when the game ends or the app backgrounds".
//
// Only a real departure counts (paused, hidden, detached); a transient `inactive` (the notification shade, a system
// dialog) does not tear the lobby down.
import 'package:flutter/widgets.dart';

class PlayServerGuard with WidgetsBindingObserver {
  PlayServerGuard({required this.onLeave});
  final VoidCallback onLeave;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      onLeave();
    }
  }
}
