// OLIVE BRANCH — starts the lost-phone watch on a GROWN-UP'S phone at boot. UNVERIFIED on a device; the pieces it wires
// are tested headless (client/test/lost_device_logic_test.dart, lost_device_screens_test.dart).
//
// Called once, right after the on-device storage is open (guardian_boot.dart). It does two things and nothing else:
//  1. Reads back the kept standing (one word in secure storage, next to the sign-in), so a lost phone that was switched off and on again is covered BEFORE it asks anyone
//     (the local auto-lock: it needs no network to start).
//  2. Tells [AuthSession] what to do when the family's server says this phone must erase its own copy: wipe the app's
//     store and its key, remember "erased", and tell the server. If it could not tell the server (no signal), it tries
//     again at its next start.
//
// A CHILD'S TABLET NEVER CALLS THIS (main_live.dart does not import it; a source test checks that), so a tablet never
// hears an erase word, never reads a standing, and nothing is ever erased from it.
import 'dart:async';

import 'auth_session.dart';
import 'device_identity.dart';
import 'device_standing.dart';
import 'local_services.dart';
import 'lost_device_logic.dart';

Future<void> startLostDeviceWatch(LocalServices services,
    {DeviceIdentityStore? identityStore, SecureKeyValueStore secure = const FlutterSecureKeyValueStore()}) async {
  final DeviceIdentityStore ids = identityStore ?? DeviceIdentityStore();
  await DeviceStanding.restore(DeviceStandingStore(secure));
  final LostPhoneCoordinator coordinator = LostPhoneCoordinator(
    wipeLocal: services.wipeAll,
    tellServer: (String deviceId, String credential) async =>
        (await AuthSession.current?.sayErased(deviceId, credential)) ?? false,
    clearIdentity: ids.clear,
  );
  DeviceStanding.onEraseOrdered = coordinator.heardErase;
  if (DeviceStanding.value == DeviceStandingState.erased) {
    // An erased phone that could not reach the server last time: the sign-in is still here until the server has heard.
    final DeviceIdentity? id = await ids.load();
    unawaited(coordinator.retryTelling(id?.deviceId, id?.deviceCredential));
  }
}
