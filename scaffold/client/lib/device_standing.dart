// OLIVE BRANCH — what THIS phone or tablet knows about its own standing with the family: normal, paused (a grown-up
// marked it as lost; it can come back), waiting for its owner's PIN (it was brought back), or cut off for good.
// UNVERIFIED on a device; pure Dart, runs headless in CI (client/test/lost_device_logic_test.dart).
//
// WHO WRITES IT. Only [AuthSession] (auth_session.dart): it is the one place that hears the server say
// `device_paused`, `pin_required` or `device_revoked`. Nothing else may set it, so a screen cannot talk a phone into
// believing it is fine. WHO READS IT. The grown-up shell's lock guard (app_lock.dart) covers the app while the state is
// not [DeviceStandingState.active]; the lost-device screens read it. A CHILD'S screens never read it: a paused or cut
// off tablet keeps working offline for her and shows her nothing at all (MASTERFILE section 2.1, P11: no remote
// control of a child's device).
import 'package:flutter/foundation.dart';

enum DeviceStandingState {
  /// The normal state.
  active,

  /// A grown-up marked this device as lost. It is refused by the family's server and locks behind its PIN. Nothing on
  /// it was erased and it can come back.
  paused,

  /// It was brought back and must show its owner's own PIN once before it gets a session again.
  needsOwnerPin,

  /// Cut off for good (the notice ended, or its owner said "It is lost"). Its family data was removed from this
  /// phone; it comes back only by being added again with a new code.
  cutOff,
}

class DeviceStanding {
  DeviceStanding._();

  static final ValueNotifier<DeviceStandingState> state = ValueNotifier<DeviceStandingState>(DeviceStandingState.active);

  /// Run once when this phone learns it was cut off for good (never on a voluntary sign-out). The grown-up app sets it
  /// to [runCutOff] (lost_device_logic.dart). A child tablet never sets it: nothing is erased from a child's tablet.
  static Future<void> Function()? onCutOff;

  static DeviceStandingState get value => state.value;
  static void set(DeviceStandingState s) {
    if (state.value != s) state.value = s;
  }

  /// Back to normal, and no hook. For test tear-downs and for a phone that was added again.
  static void reset() {
    onCutOff = null;
    state.value = DeviceStandingState.active;
  }
}
