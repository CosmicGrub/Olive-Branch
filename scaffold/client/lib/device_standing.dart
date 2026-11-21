// OLIVE BRANCH — what THIS phone or tablet knows about its own standing with the family: normal, paused (a grown-up
// marked it as lost; it can come back), waiting for its owner's PIN (it was brought back), cut off for good, or erased
// (its owner ordered it to erase its own copy and it did). UNVERIFIED on a device; pure Dart, runs headless in CI
// (client/test/lost_device_logic_test.dart).
//
// WHO WRITES IT. Only [AuthSession] (auth_session.dart) and the lost-device logic (lost_device_logic.dart): they are
// the only places that hear the server say `device_paused`, `pin_required`, `device_revoked` or the erase word. Nothing
// else may set it, so a screen cannot talk a phone into believing it is fine. WHO READS IT. The grown-up shell's
// standing guard (lost_device_screens.dart) covers the app while the state is not [DeviceStandingState.active]. A
// CHILD'S screens never read it: a paused or cut off tablet keeps working offline for her and shows her nothing at all
// (MASTERFILE section 2.1, P11: no remote control of a child's device), and nothing is ever erased from a tablet.
//
// IT SURVIVES A RESTART. The standing is kept as one word in the phone's secure storage, next to its sign-in (not in the
// on-device data catalogue: an erase wipes that store and the key that opens it, and the word "erased" has to outlive
// both). So a lost phone that is switched off and on again is still locked before it has asked anybody. That is the
// local auto-lock: it does not need the network to start.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_identity.dart' show SecureKeyValueStore;

enum DeviceStandingState {
  /// The normal state.
  active,

  /// A grown-up marked this device as lost. It is refused by the family's server and the app is covered. Nothing on it
  /// was erased and it can come back.
  paused,

  /// It was brought back and must show its owner's own PIN once before it gets a session again.
  needsOwnerPin,

  /// Cut off for good (the notice ended, or its owner said "It is lost"). It gets nothing new. What was already on it
  /// is NOT erased unless its owner also ordered that; it comes back only by being added again with a new code.
  cutOff,

  /// Its owner ordered it to erase its own copy of the family and it did. The records are still safe with the family.
  erased,
}

/// The one word kept on the device for each non-normal standing.
String? standingWord(DeviceStandingState s) => switch (s) {
      DeviceStandingState.active => null,
      DeviceStandingState.paused => 'paused',
      DeviceStandingState.needsOwnerPin => 'needs-pin',
      DeviceStandingState.cutOff => 'cut-off',
      DeviceStandingState.erased => 'erased',
    };

DeviceStandingState standingFromWord(Object? w) => switch (w) {
      'paused' => DeviceStandingState.paused,
      'needs-pin' => DeviceStandingState.needsOwnerPin,
      'cut-off' => DeviceStandingState.cutOff,
      'erased' => DeviceStandingState.erased,
      _ => DeviceStandingState.active, // fail OPEN here on purpose: an unreadable word cannot lock the owner out of their
      // own phone for good; the very next contact with the family's server says the truth again
    };

/// The on-device record of the standing: one word in secure storage. Never a name, a place or a reason.
class DeviceStandingStore {
  DeviceStandingStore(this._secure);
  final SecureKeyValueStore _secure;
  static const String _key = 'olive.device_standing';

  Future<DeviceStandingState> load() async {
    try {
      return standingFromWord(await _secure.read(_key));
    } catch (_) {
      return DeviceStandingState.active;
    }
  }

  Future<void> save(DeviceStandingState s) async {
    try {
      final String? w = standingWord(s);
      if (w == null) {
        await _secure.delete(_key);
      } else {
        await _secure.write(_key, w);
      }
    } catch (_) {
      // a full or locked store must never stop the lock itself: the in-memory standing is what covers the app
    }
  }
}

class DeviceStanding {
  DeviceStanding._();

  static final ValueNotifier<DeviceStandingState> state = ValueNotifier<DeviceStandingState>(DeviceStandingState.active);

  /// Where the standing is kept so a restart keeps the lock. Set once at boot by the grown-up app ([restore]).
  static DeviceStandingStore? store;

  /// Run once when this phone learns it was cut off for good (never on a voluntary sign-out). The grown-up app sets it
  /// (lost_device_logic.dart). A child tablet never sets it.
  static Future<void> Function()? onCutOff;

  /// Run when the family's server says this grown-up phone must erase its own copy: `(deviceId, deviceCredential)`.
  /// Only the grown-up app sets it; a child tablet never does, so the word is ignored there.
  static Future<void> Function(String deviceId, String deviceCredential)? onEraseOrdered;

  static DeviceStandingState get value => state.value;

  /// Sets the standing and keeps it. An erased phone stays erased: no later word from a server it can no longer
  /// reach changes that (only [reset], a phone that was added again, does).
  static void set(DeviceStandingState s) {
    if (state.value == DeviceStandingState.erased && s != DeviceStandingState.erased) return;
    if (state.value != s) state.value = s;
    final DeviceStandingStore? st = store;
    if (st != null) unawaited(st.save(s));
  }

  /// The owner added this phone again with a new code: whatever it was, it is a normal phone now. The only way out of
  /// "cut off" or "erased".
  static void addedAgain() {
    state.value = DeviceStandingState.active;
    final DeviceStandingStore? st = store;
    if (st != null) unawaited(st.save(DeviceStandingState.active));
  }

  /// Reads the kept standing back at boot (before any screen is drawn) and starts keeping changes.
  static Future<void> restore(DeviceStandingStore s) async {
    store = s;
    final DeviceStandingState was = await s.load();
    if (was != DeviceStandingState.active) state.value = was;
  }

  /// Back to normal, and no hooks. For test tear-downs and for a phone that was added again.
  static void reset() {
    onCutOff = null;
    onEraseOrdered = null;
    final DeviceStandingStore? st = store;
    store = null;
    state.value = DeviceStandingState.active;
    if (st != null) unawaited(st.save(DeviceStandingState.active));
  }
}
