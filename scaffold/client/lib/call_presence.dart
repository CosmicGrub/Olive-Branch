// UNVERIFIED on a real device and against Google: covered by flutter test only (MASTERFILE 7.19).
// OLIVE BRANCH — "is a call on this screen right now". Two tiny process-wide facts the incoming-call logic
// reads and nothing else owns. MASTERFILE §5.25, §5.20.
//
// A ring that arrives while the child is already on a call must never cover it (HINGE_NEVER_ENDS_CALL's
// cousin: nothing the world does may take a call out from under her), and a ring that arrives while a
// grown-up is in Guardian mode on the child's tablet must not cover the grown-up. The first fact is how
// many call screens are up (call_screen.dart counts itself in and out). The second is which kiosk surface is
// showing (kiosk_shell.dart publishes it). Both are plain notifiers so a test can set them without a widget.
import 'package:flutter/foundation.dart';

import 'lock_controller.dart' show Surface;

class CallPresence {
  CallPresence._();

  /// The number of call screens currently up (0 or 1 in practice).
  static final ValueNotifier<int> active = ValueNotifier<int>(0);
  static bool get inCall => active.value > 0;

  static void enter() => active.value = active.value + 1;
  static void leave() {
    if (active.value > 0) active.value = active.value - 1;
  }

  /// Test seam.
  @visibleForTesting
  static void reset() => active.value = 0;
}

/// The kiosk shell's current surface, or null when no kiosk shell is showing (a dev build, a test).
class KioskSurfaceSignal {
  KioskSurfaceSignal._();

  static final ValueNotifier<Surface?> current = ValueNotifier<Surface?>(null);
}
